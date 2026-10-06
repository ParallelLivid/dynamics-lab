function results = MassSpringPhysics(params)
%MASSSPRINGPHYSICS Physics engine for the mass-spring simulator.
% Coupled x1/x2 are equilibrium displacements. Physical centres are
% q1=-coll_eq_sep/2+x1 and q2=coll_eq_sep/2+x2.
% Optional params.progressFcn: @(fraction) stop; returning true stops the
% integration early (the result is then partial).
% Optional params.force_fn (single) / params.force_fn_c (coupled): @(t) F,
% a forcing profile used instead of the harmonic F0 cos(...) when forced.

params = validate_and_normalize(params);
tspan = make_output_times(params.t_end,params.dt);
opts = odeset('RelTol',1e-9,'AbsTol',1e-9);
% A force profile (a short pulse) or a contact must not fall between two
% solver steps, so those runs step no further than the output step; smooth
% runs let the solver choose its steps (they are sampled at dt either way).
if uses_profile(params) || (strcmp(params.mode,'coupled') && params.collision_on)
    opts = odeset(opts,'MaxStep',params.dt);
end
if isfield(params,'progressFcn') && ~isempty(params.progressFcn)
    opts = odeset(opts,'OutputFcn',dlab.physics.odeProgress(params.progressFcn,[0 params.t_end]));
end
switch params.mode
    case 'single', results=solve_single(params,tspan,opts);
    case 'coupled', results=solve_coupled(params,tspan,opts);
    otherwise, error('MassSpringPhysics:InvalidMode','Unsupported mode "%s".',params.mode);
end
results.mode=params.mode;
end

function p=validate_and_normalize(p)
if ~isstruct(p)||~isscalar(p), error('MassSpringPhysics:InvalidParameters','params must be a scalar struct.'); end
require_fields(p,{'mode','t_end','dt'});
if ~(ischar(p.mode)||(isstring(p.mode)&&isscalar(p.mode))), error('MassSpringPhysics:InvalidMode','mode must be ''single'' or ''coupled''.'); end
p.mode=lower(char(string(p.mode)));
if ~ismember(p.mode,{'single','coupled'}), error('MassSpringPhysics:InvalidMode','mode must be ''single'' or ''coupled''.'); end
must_scalar(p.t_end,'t_end','positive'); must_scalar(p.dt,'dt','positive');
if ceil(p.t_end/p.dt)+1>2e6
    error('MassSpringPhysics:TooManySamples','The requested output exceeds 2000000 samples. Increase dt or reduce t_end.');
end
if strcmp(p.mode,'single')
    require_fields(p,{'m','k','c','x0','v0','forced','F0','omega_f','phi_f'});
    must_scalar(p.m,'m','positive'); must_scalar(p.k,'k','positive'); must_scalar(p.c,'c','nonnegative');
    must_scalar(p.x0,'x0','finite'); must_scalar(p.v0,'v0','finite'); must_logical_scalar(p.forced,'forced');
    must_scalar(p.F0,'F0','finite'); must_scalar(p.omega_f,'omega_f','nonnegative'); must_scalar(p.phi_f,'phi_f','finite');
    p.forced=logical(p.forced);
else
    require_fields(p,{'m1','m2','k1','k2','k3','c1','c2','x1_0','v1_0','x2_0','v2_0','forced_c','F0_c','omega_fc'});
    for name={'m1','m2'}, must_scalar(p.(name{1}),name{1},'positive'); end
    for name={'k1','k2','k3','c1','c2','omega_fc'}, must_scalar(p.(name{1}),name{1},'nonnegative'); end
    for name={'x1_0','v1_0','x2_0','v2_0','F0_c'}, must_scalar(p.(name{1}),name{1},'finite'); end
    must_logical_scalar(p.forced_c,'forced_c'); p.forced_c=logical(p.forced_c);
    p=default_field(p,'collision_on',false); p=default_field(p,'e_rest',0.8);
    p=default_field(p,'coll_wall_clr',2.0); p=default_field(p,'coll_gap',0.4); p=default_field(p,'coll_eq_sep',1.5);
    must_logical_scalar(p.collision_on,'collision_on'); p.collision_on=logical(p.collision_on);
    must_scalar(p.e_rest,'e_rest','finite');
    if p.e_rest<0||p.e_rest>1, error('MassSpringPhysics:InvalidParameter','e_rest must be in [0,1].'); end
    must_scalar(p.coll_wall_clr,'coll_wall_clr','positive'); must_scalar(p.coll_gap,'coll_gap','nonnegative');
    must_scalar(p.coll_eq_sep,'coll_eq_sep','positive');
    if p.coll_eq_sep<=p.coll_gap, error('MassSpringPhysics:InvalidGeometry','The equilibrium separation must be greater than the mass–mass contact gap.'); end
    if p.collision_on
        tol=1e-10*max(1,max(abs([p.coll_wall_clr,p.coll_eq_sep,p.coll_gap])));
        surfaces=[p.x1_0+p.coll_wall_clr,p.coll_wall_clr-p.x2_0,p.coll_eq_sep+p.x2_0-p.x1_0-p.coll_gap];
        if any(surfaces < -tol), error('MassSpringPhysics:InitialPenetration','Initial positions penetrate a wall or overlap the masses.'); end
    end
end
end

function require_fields(p,names)
missing=names(~isfield(p,names));
if ~isempty(missing), error('MassSpringPhysics:MissingParameter','Missing parameter: %s.',strjoin(missing,', ')); end
end
function p=default_field(p,name,value)
if ~isfield(p,name), p.(name)=value; end
end
function must_scalar(value,name,kind)
ok=isnumeric(value)&&isreal(value)&&isscalar(value)&&isfinite(value);
if ok
    if strcmp(kind,'positive'), ok=value>0; elseif strcmp(kind,'nonnegative'), ok=value>=0; end
end
if ~ok, error('MassSpringPhysics:InvalidParameter','%s must be a real, finite %s scalar.',name,kind); end
end
function must_logical_scalar(value,name)
if ~(isscalar(value)&&(islogical(value)||(isnumeric(value)&&isfinite(value)&&ismember(value,[0 1]))))
    error('MassSpringPhysics:InvalidParameter','%s must be a logical scalar.',name);
end
end
function t=make_output_times(t_end,dt)
n=floor(t_end/dt); t=(0:n)*dt; tol=16*eps(max(1,t_end));
if t(end)<t_end-tol, t(end+1)=t_end; else, t(end)=t_end; end
if isscalar(t), t=[0,t_end]; end
end

function tf=uses_profile(p)
if strcmp(p.mode,'single')
    tf=p.forced&&isfield(p,'force_fn')&&~isempty(p.force_fn);
else
    tf=p.forced_c&&isfield(p,'force_fn_c')&&~isempty(p.force_fn_c);
end
end
function solver=choose_solver(A,t_end)
% Heavy damping makes the equations stiff: a fast decay (rate |lambda|)
% beside the slow motion. ode45 would then need about |lambda| t_end / 3
% steps just to stay stable, so such runs use ode15s.
lambda=eig(A);
fast=lambda(abs(imag(lambda))<abs(real(lambda)));
if ~isempty(fast) && max(-real(fast))*t_end>1e4
    solver=@ode15s;
else
    solver=@ode45;
end
end

function r=solve_single(p,tspan,opts)
force_fn=@(t) p.forced*p.F0*cos(p.omega_f*t+p.phi_f);
custom=uses_profile(p);
if custom, force_fn=p.force_fn; end
solver=choose_solver([0 1;-p.k/p.m -p.c/p.m],p.t_end);
[t,Y]=solver(@(t,y) single_ode(t,y,p.m,p.k,p.c,force_fn),tspan,[p.x0;p.v0],opts);
x=Y(:,1); v=Y(:,2); F_ext=p.forced*p.F0*cos(p.omega_f*t+p.phi_f);
if custom, F_ext=arrayfun(force_fn,t); end
a=(F_ext-p.c*v-p.k*x)/p.m;
r.t=t; r.x=x; r.v=v; r.a=a; r.F_ext=F_ext; r.KE=.5*p.m*v.^2; r.PE=.5*p.k*x.^2; r.E=r.KE+r.PE; r.Fspring=-p.k*x;
r.omega_n=sqrt(p.k/p.m); r.zeta=p.c/(2*sqrt(p.m*p.k)); r.omega_d=r.omega_n*sqrt(max(1-r.zeta^2,0));
if r.zeta==0, r.damp_type='Undamped';
elseif r.zeta<1-1e-10, r.damp_type='Under-damped'; elseif r.zeta>1+1e-10, r.damp_type='Over-damped'; else, r.damp_type='Critically damped'; end
r.damping=p.c;
rr=linspace(0,4,2001); omega_range=rr*r.omega_n;
r.fr_omega=omega_range; r.fr_r=rr; r.fr_MF=1./sqrt((1-rr.^2).^2+(2*r.zeta.*rr).^2); r.fr_phase=rad2deg(atan2(2*r.zeta.*rr,1-rr.^2));
if p.forced&&~custom, rval=p.omega_f/r.omega_n; r.MF_at_f=1/sqrt((1-rval^2)^2+(2*r.zeta*rval)^2); else, r.MF_at_f=NaN; end
end

function r=solve_coupled(p,tspan,opts)
force_fn=@(t) p.forced_c*p.F0_c*cos(p.omega_fc*t);
custom=uses_profile(p);
if custom, force_fn=p.force_fn_c; end
A=[0 1 0 0;-(p.k1+p.k2)/p.m1 -p.c1/p.m1 p.k2/p.m1 0;0 0 0 1;p.k2/p.m2 0 -(p.k2+p.k3)/p.m2 -p.c2/p.m2];
solver=choose_solver(A,p.t_end);
ode_fn=@(t,y) coupled_ode(t,y,p.m1,p.m2,p.k1,p.k2,p.k3,p.c1,p.c2,force_fn);
free_ode=ode_fn;
if p.collision_on
    ode_fn=@(t,y) contact_ode(t,y,free_ode,p);
end
y0=[p.x1_0;p.v1_0;p.x2_0;p.v2_0];
if ~p.collision_on
    [t_all,Y_all]=solver(ode_fn,tspan,y0,opts); coll_log=empty_collision_log();
else
    wall=p.coll_wall_clr; gap=p.coll_gap; eqsep=p.coll_eq_sep; nudge=1e-8*max(1,max([wall,gap,eqsep]));
    opts_ev=odeset(opts,'Events',@(~,y) coupled_coll_events(y,wall,gap,eqsep));
    t_all=[]; Y_all=[]; coll_log=empty_collision_log(); y_cur=y0; tspan_r=tspan(:)'; first=true; max_coll=3000;
    [resolved,initial_ids]=resolve_impacts(y_cur,p,nudge);
    if ~isempty(initial_ids)
        t_all=0; Y_all=y_cur.'; first=false;
        y_cur=resolved;
        t_all(end+1,1)=0; Y_all(end+1,:)=y_cur.';
        for id=initial_ids(:).'
            coll_log(end+1)=make_collision(0,id,collision_name(id),1,2); %#ok<AGROW>
        end
    end
    while numel(tspan_r)>=2
        [t_seg,Y_seg,t_ev,Y_ev,ie]=solver(ode_fn,tspan_r,y_cur,opts_ev);
        % The solver can report an initial-step event without terminating there.
        % Retain only the segment preceding the first impact before restarting.
        if ~isempty(t_ev)
            tc=t_ev(1);
            keep=t_seg<tc;
            t_seg=[t_seg(keep);tc]; Y_seg=[Y_seg(keep,:);Y_ev(1,:)];
        end
        if first, t_all=t_seg; Y_all=Y_seg; first=false;
        elseif numel(t_seg)>1, t_all=[t_all;t_seg(2:end)]; Y_all=[Y_all;Y_seg(2:end,:)]; %#ok<AGROW>
        end
        if isempty(t_ev), break; end
        tc=t_ev(1);
        [state,ids]=resolve_impacts(Y_ev(1,:).',p,nudge,ie(t_ev==tc));
        if isempty(ids)
            error('MassSpringPhysics:UnresolvedImpact','Collision event has no closing contact at t=%g.',tc);
        end
        if numel(coll_log)+numel(ids)>max_coll
            error('MassSpringPhysics:CollisionLimit','Exceeded %d collisions; integration aborted.',max_coll);
        end
        pre_idx=size(Y_all,1);
        t_all(end+1,1)=tc; Y_all(end+1,:)=state.'; %#ok<AGROW> Impact count is data-dependent.
        for id=ids(:).'
            coll_log(end+1)=make_collision(tc,id,collision_name(id),pre_idx,size(Y_all,1)); %#ok<AGROW>
        end
        y_cur=state; future=tspan(tspan>tc+64*eps(max(1,abs(tc))));
        if isempty(future), break; end
        tspan_r=[tc,future];
    end
end
t=t_all; x1=Y_all(:,1); v1=Y_all(:,2); x2=Y_all(:,3); v2=Y_all(:,4); F_c=p.forced_c*p.F0_c*cos(p.omega_fc*t);
if custom, F_c=arrayfun(force_fn,t); end
a1=(F_c-p.c1*v1-p.k1*x1-p.k2*(x1-x2))/p.m1; a2=(-p.c2*v2-p.k3*x2+p.k2*(x1-x2))/p.m2;
if p.collision_on
    for i=1:numel(t)
        dy=ode_fn(t(i),Y_all(i,:).');
        a1(i)=dy(2); a2(i)=dy(4);
    end
end
r.t=t; r.x1=x1; r.v1=v1; r.a1=a1; r.x2=x2; r.v2=v2; r.a2=a2; r.F_ext=F_c;
r.q1=-p.coll_eq_sep/2+x1; r.q2=p.coll_eq_sep/2+x2; r.center_gap=r.q2-r.q1;
r.KE=.5*p.m1*v1.^2+.5*p.m2*v2.^2; r.PE=.5*p.k1*x1.^2+.5*p.k3*x2.^2+.5*p.k2*(x1-x2).^2; r.E=r.KE+r.PE; r.rel=x1-x2;
r.coll_log=coll_log; if isempty(coll_log), r.coll_frames=zeros(1,0); else, r.coll_frames=[coll_log.post_idx]; end
r.geometry=struct('eq_sep',p.coll_eq_sep,'wall_clearance',p.coll_wall_clr,'contact_gap',p.coll_gap,'collision_on',p.collision_on, ...
    'springs',[p.k1 p.k2 p.k3]>0,'dampers',[p.c1 p.c2]>0);
K=[p.k1+p.k2,-p.k2;-p.k2,p.k2+p.k3]; M=diag([p.m1,p.m2]); wn=sort(sqrt(max(real(eig(K,M)),0))); r.omega_n1=wn(1); r.omega_n2=wn(2);
end

function log=empty_collision_log()
log=struct('t',{},'type_id',{},'type_str',{},'pre_idx',{},'post_idx',{});
end
function item=make_collision(t,id,type_str,pre_idx,post_idx)
item=struct('t',t,'type_id',id,'type_str',type_str,'pre_idx',pre_idx,'post_idx',post_idx);
end
function [y,impacted]=resolve_impacts(y,p,nudge,event_ids)
% Solve all touching constraints together, including stationary wall contacts
% that acquire an impulse through the other mass. Newton restitution is applied
% to closing normal velocities; nonclosing contacts must remain nonclosing.
if nargin<4, event_ids=[]; end
J=[1 0;0 -1;-1 1];
g=[y(1)+p.coll_wall_clr;p.coll_wall_clr-y(3);p.coll_eq_sep+y(3)-y(1)-p.coll_gap];
tol=1e-9*max(1,max([p.coll_wall_clr,p.coll_eq_sep,p.coll_gap]));
touching=unique([find(abs(g)<=tol);event_ids(:)]);
impacted=[];
if isempty(touching), return; end
C=J(touching,:); v=y([2 4]); normal=C*v;
if all(normal>=0), return; end
invM=diag(1./[p.m1,p.m2]); W=C*invM*C.';
target=-p.e_rest*min(normal,0);
for mask=1:2^numel(touching)-1
    active=find(bitget(mask,1:numel(touching)));
    A=W(active,active);
    if rcond(A)<1e-12, continue; end
    impulse=zeros(numel(touching),1);
    impulse(active)=A\(target(active)-normal(active));
    after=v+invM*C.'*impulse;
    if all(impulse>=-1e-12) && all(C*after-target>=-1e-12)
        impacted=touching(impulse>0);
        y([2 4])=after;
        % Separate the entire contact set consistently, never nudging one
        % mass into a wall while separating the pair.
        separation=nudge;
        if p.e_rest==0, separation=0; end
        y([1 3])=y([1 3])+invM*C.'*(W\(separation-g(touching)));
        return;
    end
end
error('MassSpringPhysics:ImpactFailure','Unable to resolve simultaneous impacts.');
end

function name=collision_name(id)
names={'m1-left wall','m2-right wall','m1-m2 impact'};
name=names{id};
end
function [val,isterm,dir]=coupled_coll_events(y,wall,gap,eqsep)
val=[y(1)+wall;wall-y(3);eqsep+y(3)-y(1)-gap]; isterm=[1;1;1]; dir=[-1;-1;-1];
speed=[y(2);-y(4);y(4)-y(2)];
rest=abs(val)<=1e-9*max(1,max([wall,gap,eqsep])) & abs(speed)<=1e-9;
val(rest)=1;
end

function dy=contact_ode(t,y,free_ode,p)
% Unilateral reactions hold resting contacts only while forces push inward.
dy=free_ode(t,y);
J=[1 0;0 -1;-1 1];
g=[y(1)+p.coll_wall_clr;p.coll_wall_clr-y(3); ...
    p.coll_eq_sep+y(3)-y(1)-p.coll_gap];
tol=1e-9*max(1,max([p.coll_wall_clr,p.coll_eq_sep,p.coll_gap]));
ids=find(abs(g)<=tol & abs(J*y([2 4]))<=1e-9);
if isempty(ids), return; end
C=J(ids,:); invM=diag(1./[p.m1,p.m2]); a=dy([2 4]);
% Enumerate active sets: reaction >= 0 and separating acceleration >= 0.
for mask=0:2^numel(ids)-1
    active=find(bitget(mask,1:numel(ids)));
    lambda=zeros(numel(ids),1);
    if ~isempty(active)
        B=C(active,:); W=B*invM*B.';
        if rcond(W)<1e-12, continue; end
        lambda(active)=-(W\(B*a));
    end
    constrained=a+invM*C.'*lambda;
    if all(lambda>=-1e-12) && all(C*constrained>=-1e-12)
        dy([2 4])=constrained;
        return;
    end
end
error('MassSpringPhysics:ContactFailure','Unable to resolve resting contact.');
end
function dydt=single_ode(t,y,m,k,c,force_fn)
dydt=[y(2);(force_fn(t)-c*y(2)-k*y(1))/m];
end
function dydt=coupled_ode(t,y,m1,m2,k1,k2,k3,c1,c2,force_fn)
x1=y(1);v1=y(2);x2=y(3);v2=y(4); dydt=[v1;(force_fn(t)-c1*v1-k1*x1-k2*(x1-x2))/m1;v2;(-c2*v2-k3*x2+k2*(x1-x2))/m2];
end
