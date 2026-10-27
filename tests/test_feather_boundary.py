"""Offline contract tests; no server, database, inventory or player is touched.

Run with Python + lupa (Lua 5.4).
"""
from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = r'''
local char = 'e5e9955d-c29e-11f1-9ae2-e0d55eaa2deb'
local horse = 'cd6d38f3-ce7f-11f1-9ad4-e0d55eaa2deb'
local assetId = '3ed76477-ce80-11f1-9ad4-e0d55eaa2deb'
session = { source=3, state='ready', characterId=char, sessionId=horse, accountId=assetId }
current, dbCalls, assetCalls, changedAfterDb, changedAfterAssets = true, 0, 0, false, false
row = { character_id=char, selected_horse_id=horse, selection_revision=19,
    horse_id=horse, owner_character_id=char, origin_operation_id=horse,
    biological_state='alive', availability='stored', projection_revision=146,
    operation_state='fulfilled', operation_character_id=char, operation_horse_id=horse,
    registration_character_id=char, registration_horse_id=horse,
    registration_state='linked', asset_id=assetId, asset_revision=1,
    model_key='a_c_horse_morgan_bay', request_id='stables.register:'..horse }
asset = { assetId=assetId, assetType='horse', status='active', managerResource='bcc-stables',
    modelKey=row.model_key, provenanceType='stable_purchase', provenanceId=horse,
    metadataVersion=1, metadata={stablesHorseId=horse}, revision=1,
    owner={holderType='character', holderId=char, interestId=assetId} }
GetResourceState = function() return 'started' end
exports = {
    ['feather-core'] = {
        RequireSession = function(_, source) return {ok=true,value=session} end,
        IsSessionCurrent = function(_, source, sid, cid)
            return current and source==3 and sid==session.sessionId and cid==char
        end
    },
    ['feather-assets'] = { GetAsset = function(_, request)
        assetCalls=assetCalls+1
        assert(request.assetId==assetId)
        if changedAfterAssets then current=false end
        return {ok=true,value=asset}
    end }
}
DB = {one=function(sql, owner)
    assert(sql:match('^SELECT ') and not sql:find('FOR UPDATE',1,true))
    assert(owner==char)
    dbCalls=dbCalls+1
    if changedAfterDb then current=false end
    return row
end}
'''


class FeatherBoundaryTest(unittest.TestCase):
    def rename(self,name='Willow',revision=1):
        self.lua.execute('''
            updates=updates or 0
            DB.one=function(sql,requested,owner)
                assert(requested==row.horse_id and owner==session.characterId)
                dbCalls=dbCalls+1;return row
            end
            exports['feather-assets'].UpdateAssetMetadata=function(_,request)
                updates=updates+1;renameRequest=request
                assert(request.expectedRevision==asset.revision)
                asset.metadata=request.metadata;asset.revision=asset.revision+1
                if staleAfterRename then current=false end
                if loseRenameReply then error('Lost acknowledgement') end
                return {ok=true,value=asset}
            end
        ''')
        return self.lua.globals().Stables.OwnedRepository.RenameOwned(
            self.lua.globals().session,self.lua.globals().row.horse_id,revision,name)

    def test_rename_uses_asset_receipt_and_preserves_other_metadata(self):
        self.lua.execute("asset.metadata.gender='female';asset.metadata.components={saddle='retained'};originalMetadata=asset.metadata")
        result=self.rename('  Étoile  ')
        self.assertTrue(result['ok'])
        self.assertEqual(result['value']['name'],'Étoile')
        self.assertEqual(result['value']['assetRevision'],2)
        self.assertIsNone(result['value']['_assetSnapshot'])
        request=self.lua.globals().renameRequest
        self.assertEqual(request['metadata']['gender'],'female')
        self.assertEqual(request['metadata']['components']['saddle'],'retained')
        self.assertEqual(request['metadata']['stablesHorseId'],self.lua.globals().row.horse_id)
        self.assertIsNone(self.lua.globals().originalMetadata.name)
        self.assertEqual(request['actorSource'],3)
        self.assertTrue(request['requestId'].startswith('stables.rename:'))

    def test_rename_rejects_invalid_names_before_read_or_write(self):
        for value in ['', '   ', 'a'*101, 'bad\nname', '<bad>', '~r~name', '\x00bad']:
            with self.subTest(value=value):
                self.assertEqual(self.rename(value)['code'],'invalid_name')
        self.assertEqual(self.lua.globals().updates,0)
        self.assertEqual(self.lua.globals().dbCalls,0)

    def test_rename_cannot_bypass_canonical_owner_or_revision(self):
        self.assertEqual(self.rename(revision=0)['code'],'invalid_name')
        self.assertEqual(self.rename(revision=2)['code'],'revision_conflict')
        self.lua.execute('asset.owner.holderId=row.asset_id')
        self.assertEqual(self.rename()['code'],'horse_not_owned')
        self.assertEqual(self.lua.globals().updates,0)

    def test_lost_rename_reply_is_observed_without_another_mutation(self):
        self.lua.globals().loseRenameReply=True
        self.assertFalse(self.rename()['ok'])
        self.lua.globals().loseRenameReply=False
        result=self.rename()
        self.assertTrue(result['ok'])
        self.assertEqual(result['value']['name'],'Willow')
        self.assertEqual(self.lua.globals().updates,1)

    def test_session_change_during_rename_never_acknowledges_to_new_session(self):
        self.lua.globals().staleAfterRename=True
        self.assertEqual(self.rename()['code'],'rename_outcome_unknown')

    def test_requested_owned_horse_uses_uuid_join_without_changing_selection(self):
        self.lua.execute('''
            row.selected_horse_id=nil
            DB.one=function(sql,requested,owner)
                assert(sql:find('horse.horse_id=?',1,true))
                assert(requested==row.horse_id and owner==session.characterId)
                return row
            end
        ''')
        result=self.lua.globals().Stables.OwnedRepository.ReadOwned(
            self.lua.globals().session,self.lua.globals().row.horse_id)
        self.assertTrue(result['ok'])
        self.assertFalse(result['value']['selected'])
        self.assertIsNone(self.lua.globals().row.selected_horse_id)

    def test_requested_horse_cannot_bypass_canonical_ownership(self):
        self.lua.execute('''
            DB.one=function() return row end
            asset.owner.holderId=row.asset_id
        ''')
        result=self.lua.globals().Stables.OwnedRepository.ReadOwned(
            self.lua.globals().session,self.lua.globals().row.horse_id)
        self.assertEqual(result['code'],'horse_not_owned')

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FIXTURE)
        for path in ('server/core/feather.lua', 'server/horse/owned_repository.lua'):
            self.lua.execute((ROOT / path).read_text(encoding='utf-8-sig'))

    def read(self, setup=''):
        self.lua.execute(setup)
        return self.lua.eval('Stables.OwnedRepository.GetSelected')(3)

    def test_existing_uuid_horse_preserved(self):
        result = self.read()
        self.assertTrue(result['ok'])
        value = result['value']
        self.assertEqual(value['horseId'], 'cd6d38f3-ce7f-11f1-9ad4-e0d55eaa2deb')
        self.assertEqual(value['selectionRevision'], 19)
        self.assertEqual(value['projectionRevision'], 146)
        self.assertEqual(self.lua.globals().dbCalls, 1)
        self.assertEqual(self.lua.globals().assetCalls, 1)

    def test_no_selected_horse(self):
        for setup in ('row=nil', 'row.selected_horse_id=nil'):
            with self.subTest(setup=setup):
                self.setUp()
                result = self.read(setup)
                self.assertTrue(result['ok'])
                self.assertFalse(result['value']['selected'])
                self.assertEqual(self.lua.globals().assetCalls, 0)

    def test_reject_corrupt_or_cross_character_links(self):
        for setup in (
            'row.owner_character_id=row.horse_id',
            'row.operation_state="paid"',
            'row.operation_horse_id=row.asset_id',
            'row.registration_character_id=row.asset_id',
            'row.registration_state="submitted"',
            'row.request_id="another-request"',
            'row.selected_horse_id=row.asset_id',
            'row.asset_revision=-1',
            'row.selection_revision=0/0',
            'row.model_key="not_a_horse"',
        ):
            with self.subTest(setup=setup):
                self.setUp()
                self.assertEqual(self.read(setup)['code'], 'horse_reconciliation_required')
                self.assertEqual(self.lua.globals().assetCalls, 0)

    def test_recheck_session_after_yields(self):
        for setup in ('current=false', 'changedAfterDb=true', 'changedAfterAssets=true'):
            with self.subTest(setup=setup):
                self.setUp()
                self.assertEqual(self.read(setup)['code'], 'session_stale')

    def test_fresh_canonical_owner_required(self):
        self.assertEqual(self.read('asset.owner.holderId=row.horse_id')['code'], 'horse_not_owned')

    def test_asset_identity_and_provenance_required(self):
        for setup in ('asset.modelKey="a_c_horse_other"', 'asset.managerResource="other"',
                      'asset.metadata.stablesHorseId=row.asset_id', 'asset.revision=0',
                      'asset.provenanceId=row.asset_id', 'asset.owner=nil'):
            with self.subTest(setup=setup):
                self.setUp()
                self.assertEqual(self.read(setup)['code'], 'horse_reconciliation_required')

    def test_provider_errors_do_not_become_missing_horses(self):
        self.assertEqual(self.read('DB.one=function() error("offline") end')['code'], 'database_unavailable')

    def test_core_result_contract_checked(self):
        self.assertEqual(self.read('exports["feather-core"].RequireSession=function() return true end')['code'],
                         'invalid_contract')

    def test_saved_condition_preserved(self):
        result=self.read('row.health_core=90; row.stamina_core=80; row.policy_revision=1; row.condition_revision=1')
        self.assertTrue(result['ok'])
        self.assertEqual(result['value']['condition']['healthCore'],90)
        self.assertEqual(result['value']['condition']['staminaCore'],80)

    def test_invalid_saved_condition_not_defaulted(self):
        result=self.read('row.health_core=101; row.stamina_core=80; row.policy_revision=1; row.condition_revision=1')
        self.assertEqual(result['code'],'horse_reconciliation_required')


if __name__ == '__main__':
    unittest.main()
