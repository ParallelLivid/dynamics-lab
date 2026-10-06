classdef TestMassSpringPhysics < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addRepoRoot(testCase)
            repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
        end
    end

    methods (Test)
        function simultaneousPairAndRightWallAtStart(testCase)
            p=contactParams(); p.x1_0=3.1; p.x2_0=2; p.v1_0=1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.t(end),p.t_end);
            testCase.verifyGreaterThanOrEqual(diff(r.t),zeros(numel(r.t)-1,1));
            testCase.verifyLessThanOrEqual(max(r.x2),2+1e-9);
            testCase.verifyGreaterThanOrEqual(min(r.center_gap),p.coll_gap-1e-9);
            testCase.verifyEqual(r.v1(2:end),zeros(size(r.v1(2:end))),'AbsTol',1e-10);
            testCase.verifyEqual(r.v2,zeros(size(r.v2)),'AbsTol',1e-10);
            testCase.verifyEqual(sort([r.coll_log.type_id]),[2 3]);
            testCase.verifyEqual([r.coll_log.t],[0 0]);
        end

        function pairStrikesMassAlreadyAtWall(testCase)
            p=contactParams(); p.x1_0=2.9; p.x2_0=2; p.v1_0=1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual([r.coll_log.t],[.2 .2],'AbsTol',1e-8);
            testCase.verifyGreaterThanOrEqual(diff(r.t),zeros(numel(r.t)-1,1));
            testCase.verifyLessThanOrEqual(max(r.x2),2+1e-9);
            testCase.verifyGreaterThanOrEqual(min(r.center_gap),p.coll_gap-1e-9);
            testCase.verifyEqual(r.v1(end),0,'AbsTol',1e-10);
            testCase.verifyEqual(r.v2(end),0,'AbsTol',1e-10);
        end

        function simultaneousContactsWithRestitution(testCase)
            p=contactParams(); p.x1_0=3.1; p.x2_0=2; p.v1_0=1; p.e_rest=.75;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.v1(end),-.75,'AbsTol',1e-10);
            testCase.verifyEqual(r.v2(end),0,'AbsTol',1e-10);
            testCase.verifyLessThanOrEqual(max(r.x2),2+1e-9);
            testCase.verifyGreaterThanOrEqual(min(r.center_gap),p.coll_gap-1e-9);
        end

        function lowNaturalFrequencyResponseIncludesStaticAndResonance(testCase)
            p=singleParams(); p.m=1000; p.k=.001;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.fr_r([1 end]),[0 4]);
            testCase.verifyGreaterThan(diff(r.fr_omega),zeros(1,numel(r.fr_omega)-1));
            testCase.verifyEqual(r.fr_MF(1),1);
            idx=find(r.fr_r==1);
            testCase.verifyNumElements(idx,1);
            testCase.verifyEqual(r.fr_MF(idx),1/(2*r.zeta),'AbsTol',1e-12);
        end

        function sustainedWallContact(testCase)
            p=contactParams(); p.x1_0=-p.coll_wall_clr; p.v1_0=-1;
            p.F0_c=-1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.t(end),p.t_end);
            testCase.verifyNumElements(r.coll_log,1);
            testCase.verifyEqual(r.x1,-p.coll_wall_clr*ones(size(r.x1)),'AbsTol',1e-8);
            testCase.verifyEqual(r.v1(2:end),zeros(size(r.v1(2:end))),'AbsTol',1e-8);
            testCase.verifyEqual(r.a1(2:end),zeros(size(r.a1(2:end))),'AbsTol',1e-8);
        end

        function restingContactReleasesWhenForceReverses(testCase)
            p=contactParams(); p.x1_0=-p.coll_wall_clr;
            p.F0_c=-1; p.omega_fc=pi; p.t_end=1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEmpty(r.coll_log);
            before=r.t<=.5;
            testCase.verifyEqual(r.x1(before),-2*ones(sum(before),1),'AbsTol',1e-7);
            testCase.verifyEqual(r.x1(end),-2+1/(2*pi)-1/pi^2,'AbsTol',1e-6);
            testCase.verifyEqual(r.v1(end),1/pi,'AbsTol',1e-6);
        end

        function impactTransitionsToRestingContact(testCase)
            p=contactParams(); p.x1_0=-1.9; p.F0_c=-1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyNumElements(r.coll_log,1);
            event=r.coll_log(1);
            testCase.verifyEqual(event.t,sqrt(.2),'AbsTol',1e-7);
            testCase.verifyEqual(r.x1(event.post_idx:end), ...
                -2*ones(size(r.x1(event.post_idx:end))),'AbsTol',1e-7);
            testCase.verifyEqual(r.t(end),1);
        end

        function massesRemainInContactUnderCompression(testCase)
            p=contactParams(); p.x1_0=.55; p.x2_0=-.55; p.F0_c=1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEmpty(r.coll_log);
            testCase.verifyEqual(r.center_gap,.4*ones(size(r.t)),'AbsTol',1e-7);
            testCase.verifyEqual(r.a1,.5*ones(size(r.t)),'AbsTol',1e-7);
            testCase.verifyEqual(r.a2,r.a1,'AbsTol',1e-7);
        end

        function restingRightWall(testCase)
            p=contactParams(); p.x2_0=2; p.k2=1; p.x1_0=3.05;
            p.t_end=.1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.x2,2*ones(size(r.t)),'AbsTol',1e-7);
            testCase.verifyEqual(r.a2,zeros(size(r.t)),'AbsTol',1e-7);
        end
        function singleUndampedMatchesAnalytic(testCase)
            p=singleParams(); p.c=0; p.t_end=5; p.dt=.01;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            expected=p.x0*cos(sqrt(p.k/p.m)*r.t)+p.v0/sqrt(p.k/p.m)*sin(sqrt(p.k/p.m)*r.t);
            testCase.verifyLessThan(max(abs(r.x-expected)),1e-8);
            testCase.verifyLessThan((max(r.E)-min(r.E))/r.E(1),1e-8);
        end

        function includesExactEndTime(testCase)
            p=singleParams(); p.t_end=1; p.dt=.3;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.t(end),1,'AbsTol',eps);
        end

        function rejectsInvalidParameters(testCase)
            p=singleParams(); p.m=0;
            testCase.verifyError(@() dlab.sims.massspring.MassSpringPhysics(p),'MassSpringPhysics:InvalidParameter');
            p=singleParams(); p.dt=-1;
            testCase.verifyError(@() dlab.sims.massspring.MassSpringPhysics(p),'MassSpringPhysics:InvalidParameter');
            p=singleParams(); p.mode='typo';
            testCase.verifyError(@() dlab.sims.massspring.MassSpringPhysics(p),'MassSpringPhysics:InvalidMode');
        end

        function elasticCoupledImpactUsesPhysicalSeparation(testCase)
            p=coupledParams(); p.k1=0; p.k2=0; p.k3=0; p.c1=0; p.c2=0;
            p.e_rest=1; p.coll_eq_sep=1.5; p.coll_gap=.4;
            p.x1_0=0; p.v1_0=1; p.x2_0=0; p.v2_0=-1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyNumElements(r.coll_log,1);
            event=r.coll_log(1);
            testCase.verifyEqual(r.center_gap(event.pre_idx),p.coll_gap,'AbsTol',1e-7);
            testCase.verifyEqual(r.t(event.pre_idx),r.t(event.post_idx),'AbsTol',eps);
            testCase.verifyEqual(r.v1(event.pre_idx),1,'AbsTol',1e-10);
            testCase.verifyEqual(r.v1(event.post_idx),-1,'AbsTol',1e-10);
            testCase.verifyEqual(r.v2(event.post_idx),1,'AbsTol',1e-10);
            testCase.verifyEqual(r.t(end),p.t_end,'AbsTol',eps);
        end

        function wallImpactAndRestitution(testCase)
            p=coupledParams(); p.k1=0; p.k2=0; p.k3=0; p.c1=0; p.c2=0;
            p.x1_0=-1.5; p.v1_0=-1; p.x2_0=0; p.v2_0=0; p.e_rest=.6;
            r=dlab.sims.massspring.MassSpringPhysics(p); event=r.coll_log(1);
            testCase.verifyEqual(event.type_id,1);
            testCase.verifyEqual(r.v1(event.post_idx),.6,'AbsTol',1e-10);
        end

        function resolvesClosingContactAtInitialTime(testCase)
            p=coupledParams(); p.k1=0; p.k2=0; p.k3=0; p.c1=0; p.c2=0;
            p.x1_0=(p.coll_eq_sep-p.coll_gap)/2;
            p.x2_0=-p.x1_0; p.v1_0=1; p.v2_0=-1; p.e_rest=1;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.coll_log(1).t,0,'AbsTol',eps);
            testCase.verifyEqual(r.v1(r.coll_log(1).post_idx),-1,'AbsTol',1e-10);
        end

        function rejectsInitialPenetration(testCase)
            p=coupledParams(); p.x1_0=1; p.x2_0=-1;
            testCase.verifyError(@() dlab.sims.massspring.MassSpringPhysics(p),'MassSpringPhysics:InitialPenetration');
        end

        function coupledFrequenciesMatchEigenproblem(testCase)
            p=coupledParams(); p.collision_on=false;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            K=[p.k1+p.k2,-p.k2;-p.k2,p.k2+p.k3];
            expected=sort(sqrt(eig(K,diag([p.m1,p.m2]))));
            testCase.verifyEqual([r.omega_n1;r.omega_n2],expected,'AbsTol',1e-12);
        end

        function forcedSteadyStateMatchesMagnificationFactor(testCase)
            % Independent reference: the closed-form magnification factor.
            % Classic steady state: X = (F0/k) / sqrt((1-r^2)^2 + (2 zeta r)^2),
            % lagging the force by atan2(2 zeta r, 1 - r^2). Fit the tail.
            for ratio = [0.5 1 2]
                p=singleParams(); p.forced=true; p.x0=0; p.t_end=140; p.dt=.005;
                wn=sqrt(p.k/p.m); zeta=p.c/(2*sqrt(p.m*p.k)); p.omega_f=ratio*wn;
                r=dlab.sims.massspring.MassSpringPhysics(p);
                tail=r.t>100;
                co=[cos(p.omega_f*r.t(tail)) sin(p.omega_f*r.t(tail))]\r.x(tail);
                MF=1/sqrt((1-ratio^2)^2+(2*zeta*ratio)^2);
                testCase.verifyEqual(hypot(co(1),co(2))/(p.F0/p.k),MF,'RelTol',1e-6);
                testCase.verifyEqual(atan2d(co(2),co(1)),atan2d(2*zeta*ratio,1-ratio^2),'AbsTol',1e-4);
                testCase.verifyEqual(r.MF_at_f,MF,'RelTol',1e-12);
            end
        end

        function freeResponseMatchesDampedOscillator(testCase)
            % Defaults: wn = sqrt(10), zeta = 0.5/(2 sqrt(10)), Td = 2 pi / wd.
            p=singleParams(); p.t_end=20; p.dt=1e-3;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual([r.omega_n r.zeta],[3.16227766016838 0.0790569415042095],'RelTol',1e-12);
            s=sign(r.x); i=find(s(1:end-1)<0 & s(2:end)>=0);
            up=r.t(i)-r.x(i).*(r.t(i+1)-r.t(i))./(r.x(i+1)-r.x(i));
            testCase.verifyEqual(mean(diff(up)),1.99315602848789,'AbsTol',1e-6);
            wd=r.omega_d; a=r.zeta*r.omega_n;
            testCase.verifyEqual(r.x,exp(-a*r.t).*(cos(wd*r.t)+a/wd*sin(wd*r.t)),'AbsTol',1e-8);
        end

        function beatingModesAreRootTenAndRootEleven(testCase)
            p=coupledParams(); p.collision_on=false; p.k1=10; p.k2=.5; p.k3=10; p.c1=0; p.c2=0;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual([r.omega_n1 r.omega_n2],[sqrt(10) sqrt(11)],'RelTol',1e-12);
        end

        function undampedIsNamedUndamped(testCase)
            p=singleParams(); p.c=0;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(string(r.damp_type),"Undamped");
            p.c=.5; r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(string(r.damp_type),"Under-damped");
        end

        function heavyDampingSolvesQuicklyAndAccurately(testCase)
            % zeta = 1.6e4: stiff. Over-damped closed form from rest at x0.
            p=singleParams(); p.c=1e5; p.t_end=20; p.dt=1e-3;
            started=tic; r=dlab.sims.massspring.MassSpringPhysics(p); seconds=toc(started);
            testCase.verifyLessThan(seconds,10,"A heavily damped run must not crawl.");
            wn=sqrt(p.k/p.m); z=p.c/(2*sqrt(p.m*p.k));
            s1=-wn*(z-sqrt(z^2-1)); s2=-wn*(z+sqrt(z^2-1));
            A=-s2*p.x0/(s1-s2); B=p.x0-A;
            testCase.verifyEqual(r.x(end),A*exp(s1*p.t_end)+B*exp(s2*p.t_end),'AbsTol',1e-7);
        end

        function impactsLoseTheEnergyRestitutionPredicts(testCase)
            % Wall: KE after / before = e^2. Pair: loss = mu (1 - e^2) vrel^2 / 2.
            p=coupledParams(); p.k1=0; p.k2=0; p.k3=0; p.c1=0; p.c2=0; p.e_rest=.6;
            p.x1_0=-1.5; p.v1_0=-1; p.x2_0=0; p.v2_0=0;
            r=dlab.sims.massspring.MassSpringPhysics(p); c=r.coll_log(1);
            testCase.verifyEqual(c.type_id,1);
            testCase.verifyEqual(r.KE(c.post_idx)/r.KE(c.pre_idx),p.e_rest^2,'AbsTol',1e-12);
            % Springs, dampers, and impacts: E0 - E(T) = damping work + impact losses.
            p=coupledParams(); p.e_rest=.7; p.x1_0=-1.2; p.v1_0=-6; p.x2_0=.5; p.v2_0=7;
            p.t_end=20; p.dt=5e-4;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.assertGreaterThan(numel(r.coll_log),2);
            mu=p.m1*p.m2/(p.m1+p.m2); lost=0;
            for c=r.coll_log
                a=c.pre_idx;
                switch c.type_id
                    case 1, expected=.5*p.m1*(1-p.e_rest^2)*r.v1(a)^2;
                    case 2, expected=.5*p.m2*(1-p.e_rest^2)*r.v2(a)^2;
                    otherwise, expected=.5*mu*(1-p.e_rest^2)*(r.v1(a)-r.v2(a))^2;
                end
                testCase.verifyEqual(r.E(a)-r.E(c.post_idx),expected,'AbsTol',1e-5);
                lost=lost+expected;
            end
            h=diff(r.t); damping=sum(h.*(p.c1*(r.v1(1:end-1).^2+r.v1(2:end).^2)+p.c2*(r.v2(1:end-1).^2+r.v2(2:end).^2))/2);
            testCase.verifyEqual(r.E(1)-r.E(end),damping+lost,'RelTol',1e-5);
        end

        function geometryErrorIsReadable(testCase)
            p=coupledParams(); p.coll_gap=2;
            try
                dlab.sims.massspring.MassSpringPhysics(p);
                testCase.verifyFail("A contact gap wider than the separation must be rejected.");
            catch err
                testCase.verifyEqual(string(err.identifier),"MassSpringPhysics:InvalidGeometry");
                testCase.verifySubstring(string(err.message),"equilibrium separation");
            end
        end

        function geometryListsTheSpringsAndDampersPresent(testCase)
            p=coupledParams(); p.k2=0; p.c1=0;
            r=dlab.sims.massspring.MassSpringPhysics(p);
            testCase.verifyEqual(r.geometry.springs,[true false true]);
            testCase.verifyEqual(r.geometry.dampers,[false true]);
        end

        function bodeMatchesTheReceptance(testCase)
            % Force -> x is 1/(k - m w^2 + i c w); coupled, by Cramer's rule.
            plugin=dlab.sims.massspring.MassSpringPlugin();
            p=plugin.defaultParams();
            S=dlab.core.FrequencyResponse.model(plugin.linearization(p));
            w=[.1 1 3 sqrt(10) 5 30]';
            R=dlab.core.FrequencyResponse.response(S,"Force","x",w);
            testCase.verifyEqual(R.Response,1./(p.k-p.m*w.^2+1i*p.c*w),'RelTol',1e-9);
            testCase.verifyEqual(string(S.InputUnits),"N");
            testCase.verifyEqual(string(S.OutputUnits),["m" "m/s"]);
            q=p; q.mode="coupled";
            S=dlab.core.FrequencyResponse.model(plugin.linearization(q));
            D=(q.k1+q.k2-q.m1*w.^2+1i*q.c1*w).*(q.k2+q.k3-q.m2*w.^2+1i*q.c2*w)-q.k2^2;
            R1=dlab.core.FrequencyResponse.response(S,1,1,w); R2=dlab.core.FrequencyResponse.response(S,1,3,w);
            testCase.verifyEqual(R1.Response,(q.k2+q.k3-q.m2*w.^2+1i*q.c2*w)./D,'RelTol',1e-9);
            testCase.verifyEqual(R2.Response,q.k2./D,'RelTol',1e-9);
        end
    end
end

function p=singleParams()
p=struct('mode','single','t_end',2,'dt',.01,'m',1,'k',10,'c',.5, ...
    'x0',1,'v0',0,'forced',false,'F0',2,'omega_f',3,'phi_f',0);
end

function p=contactParams()
p=coupledParams(); p.k1=0; p.k2=0; p.k3=0; p.c1=0; p.c2=0;
p.e_rest=0; p.forced_c=true; p.omega_fc=0; p.t_end=1;
end

function p=coupledParams()
p=struct('mode','coupled','t_end',2,'dt',.01,'m1',1,'m2',1, ...
    'k1',8,'k2',4,'k3',6,'c1',.3,'c2',.3, ...
    'x1_0',0,'v1_0',0,'x2_0',0,'v2_0',0, ...
    'forced_c',false,'F0_c',0,'omega_fc',1, ...
    'collision_on',true,'e_rest',.8,'coll_wall_clr',2, ...
    'coll_eq_sep',1.5,'coll_gap',.4);
end
