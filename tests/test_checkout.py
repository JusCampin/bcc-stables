"""Checkout uses isolated SQL and provider doubles; no real balances/items touched."""
import json
import sqlite3
import unittest
import uuid
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT, FIXTURE
from test_call_repository import CHAR, ASSET

SCHEMA="""
CREATE TABLE fs_character_stables(character_id TEXT PRIMARY KEY,selected_horse_id TEXT,revision INTEGER DEFAULT 0);
CREATE TABLE fs_operations(operation_id TEXT PRIMARY KEY,kind TEXT DEFAULT 'horse_purchase',character_id TEXT,horse_id TEXT UNIQUE,
 quote_id TEXT,catalog_id TEXT,catalog_revision INTEGER,currency TEXT,amount INTEGER CHECK(amount>0),wallet_account_id TEXT,sink_account_id TEXT,
 payment_key TEXT UNIQUE,fingerprint TEXT,state TEXT,revision INTEGER,payment_transaction_id TEXT UNIQUE,record_json TEXT,next_attempt_at TEXT,
 updated_at TEXT DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE fs_horses(horse_id TEXT PRIMARY KEY,owner_character_id TEXT,origin_operation_id TEXT UNIQUE REFERENCES fs_operations(operation_id),catalog_id TEXT,
 catalog_revision INTEGER,biological_state TEXT DEFAULT 'alive',availability TEXT DEFAULT 'stored',revision INTEGER DEFAULT 0);
CREATE TABLE fs_asset_registrations(operation_id TEXT PRIMARY KEY,character_id TEXT,horse_id TEXT UNIQUE,request_id TEXT UNIQUE,model_key TEXT,
 fingerprint TEXT,request_json TEXT,state TEXT DEFAULT 'prepared',asset_id TEXT UNIQUE,asset_revision INTEGER,revision INTEGER DEFAULT 0);
CREATE TABLE fs_horse_history(event_id TEXT PRIMARY KEY,horse_id TEXT,operation_id TEXT,event_kind TEXT,facts_json TEXT,UNIQUE(operation_id,event_kind));
CREATE TABLE fs_outbox(event_id TEXT PRIMARY KEY,operation_id TEXT,event_name TEXT,payload_json TEXT,UNIQUE(operation_id,event_name));
CREATE TABLE fs_call_slots(character_id TEXT PRIMARY KEY,generation_id TEXT);
CREATE TABLE fs_care_operations(operation_id TEXT PRIMARY KEY,character_id TEXT,state TEXT);
CREATE TABLE fs_horse_condition(horse_id TEXT PRIMARY KEY,health_core INTEGER,stamina_core INTEGER,policy_revision INTEGER,revision INTEGER);
"""

class CheckoutTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FIXTURE)
        self.db=sqlite3.connect(':memory:');self.db.row_factory=sqlite3.Row
        self.db.executescript(SCHEMA)
        self.db.create_function('UUID',0,lambda:str(uuid.uuid4()))
        self.inside=False;self.fail_history=False;self.lost_commit=False
        self.lua.globals().json=self.lua.table_from({'encode':lambda v:json.dumps(self.python(v),ensure_ascii=False,separators=(',',':')),
            'decode':lambda s:self.table(json.loads(s))})
        self.lua.globals().DB=self.lua.table_from({'one':self.one,'query':self.query,'exec':self.execute,'transaction':self.transaction})
        self.lua.execute((ROOT/'server/core/feather.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT/'server/horse/owned_repository.lua').read_text(encoding='utf-8'))
        self.lua.execute("""
            Config={commerce={purchasesEnabled=true},horseLimits={player=5}}
            StableLocations={valentine={shop={jobsEnabled=false,hours={active=false}},trainerBuy=false}}
            Horses={ModelToBreedMap={a_c_horse_morgan_bay={breed='Morgan'}},BreedCatalog={Morgan={colors={a_c_horse_morgan_bay={currency=3,cashPrice=75,goldPrice=3}}}}}
            Authorize=function() return current end
            paymentCalls=0;charges=0;registrations=0;balance=100000;receipts={};assets={};registered={}
            exports['feather-economy']={
                FindAccountsByOwner=function(_,p) return {ok=true,value={{accountId=asset.assetId,ownerType='character',ownerId=p.ownerId,accountType='wallet',currency='dollars',status='open'},{accountId='11111111-1111-1111-1111-111111111111',ownerType='character',ownerId=p.ownerId,accountType='wallet',currency='gold',status='open'}}} end,
                GetSystemAccount=function(_,p) return {ok=true,value={accountId=session.sessionId,accountType='system_sink',currency=p.currency,status='open'}} end,
                Transfer=function(_,p)
                    paymentCalls=paymentCalls+1
                    local receipt=receipts[p.idempotencyKey]
                    if not receipt then
                        if balance<p.amount then return {ok=false,code='insufficient_funds',message='Insufficient'} end
                        balance=balance-p.amount;charges=charges+1
                        receipt={transactionId=p.referenceId,amount=p.amount,currency=p.currency,fromAccountId=p.fromAccountId,toAccountId=p.toAccountId,
                            referenceId=p.referenceId,referenceType=p.referenceType,sourceResource='bcc-stables',reasonCode=p.reasonCode}
                        receipts[p.idempotencyKey]=receipt
                    end
                    if losePayment then losePayment=false;return {ok=false,code='timeout',message='Reply lost'} end
                    return {ok=true,value=receipt}
                end,
            }
            exports['feather-assets'].RegisterAsset=function(_,p)
                local a=registered[p.requestId]
                if not a then
                    registrations=registrations+1
                    a={assetId=p.provenanceId,assetType=p.assetType,modelKey=p.modelKey,metadataVersion=p.metadataVersion,metadata=p.metadata,
                        managerResource='bcc-stables',status='active',provenanceType=p.provenanceType,provenanceId=p.provenanceId,revision=1,
                        owner={holderType=p.holderType,holderId=p.holderId,interestId=p.provenanceId}}
                    registered[p.requestId]=a;assets[a.assetId]=a
                end
                if loseAsset then loseAsset=false;return {ok=false,code='timeout',message='Reply lost'} end
                return {ok=true,value=a}
            end
            exports['feather-assets'].GetAsset=function(_,p) return {ok=true,value=assets[p.assetId]} end
        """)
        self.load()

    def load(self):
        self.lua.execute((ROOT/'server/horse/checkout.lua').read_text(encoding='utf-8'))
        self.checkout=self.lua.globals().Stables.Checkout

    def tearDown(self): self.db.close()
    def table(self,value): return self.lua.table_from(value,recursive=True) if isinstance(value,(dict,list)) else value
    def python(self,value):
        if hasattr(value,'items'): return {k:self.python(v) for k,v in value.items()}
        return value
    def sql(self,sql):
        return sql.replace(' FOR UPDATE','').replace('INSERT IGNORE','INSERT OR IGNORE').replace('DATE_ADD(UTC_TIMESTAMP(),INTERVAL 10 SECOND)',"datetime('now','+10 seconds')").replace('UTC_TIMESTAMP()','CURRENT_TIMESTAMP')
    def one(self,sql,*args):
        row=self.db.execute(self.sql(sql),args).fetchone()
        return self.table(dict(row)) if row else None
    def query(self,sql,*args): return self.table([dict(r) for r in self.db.execute(self.sql(sql),args).fetchall()])
    def execute(self,sql,*args):
        if self.fail_history and 'INSERT INTO fs_horse_history' in sql: raise RuntimeError('injected failure')
        result=self.db.execute(self.sql(sql),args).rowcount
        if not self.inside:self.db.commit()
        return result
    def transaction(self,fn):
        self.inside=True
        try:
            self.db.execute('BEGIN')
            result=fn(self.lua.globals().DB)
            if result is True:self.db.commit()
            else:self.db.rollback()
            if result is True and self.lost_commit:
                self.lost_commit=False;raise RuntimeError('lost commit reply')
            return result
        except:
            self.db.rollback();raise
        finally:self.inside=False
    def quote(self,**changes):
        p={'modelKey':'a_c_horse_morgan_bay','name':'Willow','gender':'female','currency':'dollars',**changes}
        return self.checkout.Quote(self.lua.globals().session,'valentine',self.table(p),self.lua.globals().Authorize)
    def confirm(self,q,**changes):
        return self.checkout.Confirm(self.lua.globals().session,'valentine',self.table({'operationId':q['operationId'],'amount':q['amount'],'currency':q['currency'],**changes}),self.lua.globals().Authorize)
    def count(self,table): return self.db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0]

    def test_complete_purchase_and_replay_charge_and_create_once(self):
        q=self.quote()['value'];r=self.confirm(q)
        self.assertTrue(r['ok']);self.assertEqual(r['value']['state'],'fulfilled')
        self.assertTrue(self.confirm(q)['ok'])
        self.assertEqual(self.lua.globals().charges,1);self.assertEqual(self.lua.globals().registrations,1)
        for table in ['fs_horses','fs_asset_registrations','fs_horse_history','fs_outbox','fs_horse_condition']:self.assertEqual(self.count(table),1)
        self.assertEqual(self.db.execute('SELECT selected_horse_id FROM fs_character_stables').fetchone()[0],q['horseId'])
        self.assertEqual(self.lua.globals().assets[q['horseId']]['metadata']['gender'],'female')
        owned=self.lua.globals().Stables.OwnedRepository.ReadSelected(self.lua.globals().session)
        self.assertTrue(owned['ok'])
        self.assertEqual(owned['value']['gender'],'female')
        self.assertEqual(owned['value']['condition']['healthCore'],100)

    def test_insufficient_funds_leaves_no_horse_or_payment(self):
        self.lua.globals().balance=1;q=self.quote()['value']
        self.assertEqual(self.confirm(q)['code'],'insufficient_funds')
        self.assertEqual(self.lua.globals().charges,0);self.assertEqual(self.count('fs_horses'),0)
        self.assertEqual(self.db.execute('SELECT state FROM fs_operations').fetchone()[0],'cancelled')

    def test_changed_or_expired_price_and_acknowledgement_refused(self):
        q=self.quote()['value']
        self.assertEqual(self.confirm(q,amount=1)['code'],'price_conflict')
        self.lua.execute('Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.cashPrice=76')
        self.assertEqual(self.confirm(q)['code'],'quote_expired')
        self.assertEqual(self.lua.globals().charges,0)

    def test_capacity_and_restricted_models_refuse_before_payment(self):
        q=self.quote()['value'];self.lua.execute('Config.horseLimits.player=0')
        self.assertEqual(self.confirm(q)['code'],'horse_limit')
        self.lua.execute("Horses.JobLocks={police={'a_c_horse_morgan_bay'}}")
        self.assertEqual(self.quote()['code'],'purchase_restricted')
        self.assertEqual(self.lua.globals().charges,0)

    def test_lost_payment_reply_recovers_offline_after_resource_restart(self):
        q=self.quote()['value'];self.lua.globals().losePayment=True
        self.assertEqual(self.confirm(q)['code'],'purchase_pending')
        self.load();self.lua.globals().current=False
        self.checkout.Tick()
        self.assertEqual(self.lua.globals().charges,1)
        self.assertEqual(self.db.execute('SELECT state FROM fs_operations').fetchone()[0],'fulfilled')

    def test_lost_asset_reply_recovers_without_duplicate_asset(self):
        q=self.quote()['value'];self.lua.globals().loseAsset=True
        self.assertEqual(self.confirm(q)['code'],'purchase_pending')
        self.load();self.assertTrue(self.confirm(q)['ok'])
        self.assertEqual(self.lua.globals().charges,1);self.assertEqual(self.lua.globals().registrations,1)

    def test_atomic_projection_failure_and_lost_commit_reply(self):
        q=self.quote()['value'];self.fail_history=True
        self.assertEqual(self.confirm(q)['code'],'purchase_pending')
        self.assertEqual(self.count('fs_horses'),0);self.assertEqual(self.count('fs_horse_history'),0)
        self.fail_history=False;self.lost_commit=True
        self.assertEqual(self.confirm(q)['code'],'purchase_pending')
        self.assertTrue(self.confirm(q)['ok']);self.assertEqual(self.count('fs_horses'),1)
        self.assertEqual(self.lua.globals().charges,1)

    def test_new_order_is_fenced_while_previous_payment_is_unknown(self):
        q=self.quote()['value'];self.lua.globals().losePayment=True;self.confirm(q)
        other=self.quote()['value']
        self.assertEqual(self.confirm(other)['code'],'purchase_pending')
        self.assertEqual(self.lua.globals().charges,1)

    def test_invalid_name_free_price_and_foreign_quote_do_not_charge(self):
        self.assertEqual(self.quote(name='<bad>')['code'],'invalid_name')
        q=self.quote()['value']
        self.lua.execute("session.characterId='11111111-1111-1111-1111-111111111111'")
        self.assertEqual(self.confirm(q)['code'],'purchase_not_found')
        self.lua.execute('Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.currency=4')
        self.assertEqual(self.quote()['code'],'free_purchase_unavailable')
        self.assertEqual(self.lua.globals().charges,0)

    def test_recovery_does_not_change_selection_under_active_call(self):
        q=self.quote()['value']
        self.db.execute('INSERT INTO fs_call_slots VALUES (?,?)',(CHAR,ASSET));self.db.commit()
        self.assertTrue(self.confirm(q)['ok'])
        self.assertIsNone(self.db.execute('SELECT selected_horse_id FROM fs_character_stables').fetchone()[0])
        self.assertEqual(self.count('fs_horses'),1)

    def test_gold_price_is_converted_to_smallest_units(self):
        q=self.quote(currency='gold')['value']
        self.assertEqual(q['amount'],300)
        self.assertTrue(self.confirm(q)['ok'])
        self.assertEqual(self.lua.globals().balance,99700)

    def test_quote_expiry_disabled_gate_and_stale_session_do_not_charge(self):
        q=self.quote()['value']
        record=json.loads(self.db.execute('SELECT record_json FROM fs_operations').fetchone()[0]);record['expiresAt']=0
        self.db.execute('UPDATE fs_operations SET record_json=?',(json.dumps(record),));self.db.commit()
        self.assertEqual(self.confirm(q)['code'],'quote_expired')
        self.lua.execute('Config.commerce.purchasesEnabled=false')
        self.assertEqual(self.quote()['code'],'purchase_disabled')
        self.lua.execute('Config.commerce.purchasesEnabled=true;current=false')
        self.assertEqual(self.quote()['code'],'session_stale')
        self.assertEqual(self.lua.globals().charges,0)

    def test_fresh_foreign_ownership_prevents_projection_from_old_registration_reply(self):
        q=self.quote()['value']
        self.lua.execute("exports['feather-assets'].GetAsset=function(_,p) local a=assets[p.assetId];a.owner.holderId='11111111-1111-1111-1111-111111111111';return {ok=true,value=a} end")
        self.assertEqual(self.confirm(q)['code'],'purchase_pending')
        self.assertEqual(self.count('fs_horses'),0)
        self.assertEqual(self.db.execute('SELECT state FROM fs_operations').fetchone()[0],'paid')
        self.assertEqual(self.lua.globals().charges,1)

    def test_unconfirmed_quotes_never_charge_on_recovery(self):
        self.quote();self.load();self.checkout.Tick()
        self.assertEqual(self.lua.globals().charges,0)

if __name__=='__main__':unittest.main()
