-- Surveyed course geometry shared for display; the server owns progression.
Stables=Stables or {};Stables.TrainingCourse={}
local C=Stables.TrainingCourse
function C.Distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
function C.Inside(p,area,tolerance)
    local boundary=area.boundary
    if not boundary or #boundary<3 then return C.Distance(p,area.center)<=area.radius end
    local inside,nearest=false,math.huge
    local j=#boundary
    for i,a in ipairs(boundary) do
        local b=boundary[j]
        if (a.y>p.y)~=(b.y>p.y) and p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x then inside=not inside end
        local dx,dy=b.x-a.x,b.y-a.y;local length=dx*dx+dy*dy
        local t=length>0 and math.max(0,math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) or 0
        nearest=math.min(nearest,math.sqrt((p.x-a.x-t*dx)^2+(p.y-a.y-t*dy)^2));j=i
    end
    return inside or nearest<=math.max(area.boundaryTolerance or 0,tolerance or 0)
end
function C.AtCheckpoint(p,point,radius)
    return (p.x-point.x)^2+(p.y-point.y)^2<=radius*radius and math.abs(p.z-point.z)<=8
end
function C.Points(area,mode)
    local course=area.courses and area.courses[mode]
    local policy=Config.training.courses[mode]
    if not course or not policy or type(course.checkpoints)~='table' or #course.checkpoints<2 then return nil end
    local points={};local laps=course.laps or policy.laps
    for _=1,laps do for _,p in ipairs(course.checkpoints) do points[#points+1]={x=p.x,y=p.y,z=p.z} end end
    return points,laps
end
function C.Reward(base,elapsed,limit)
    local target=limit*0.55
    local score=elapsed<=target and 100 or math.max(60,math.floor(100-(elapsed-target)/math.max(1,limit-target)*40+0.5))
    return math.max(1,math.floor(base*(0.6+(score-60)/40*0.4)+0.5)),score
end
