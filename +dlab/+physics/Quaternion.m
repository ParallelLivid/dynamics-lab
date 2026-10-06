classdef Quaternion
    %QUATERNION Unit-quaternion attitude helpers (scalar first: [w x y z]).
    %   Quaternions are 4×1 double columns; q rotates body vectors into the
    %   world frame, matching dlab.physics.eulerToDcm.
    %
    %       q = dlab.physics.Quaternion.fromEuler(phi, theta, psi);
    %       R = dlab.physics.Quaternion.toDcm(q);
    %       dq = dlab.physics.Quaternion.derivative(q, [p; q; r]);
    %       qe = dlab.physics.Quaternion.relative(qTarget, q);   % error

    methods (Static)
        function q = fromEuler(phi, theta, psi)
            %FROMEULER Quaternion of 3-2-1 Euler angles (rad).
            c = cos([phi theta psi] / 2);
            s = sin([phi theta psi] / 2);
            q = [c(1)*c(2)*c(3) + s(1)*s(2)*s(3)
                 s(1)*c(2)*c(3) - c(1)*s(2)*s(3)
                 c(1)*s(2)*c(3) + s(1)*c(2)*s(3)
                 c(1)*c(2)*s(3) - s(1)*s(2)*c(3)];
        end

        function [phi, theta, psi] = toEuler(q)
            %TOEULER 3-2-1 Euler angles (rad) of a unit quaternion.
            q = dlab.physics.Quaternion.normalize(q);
            [w, x, y, z] = deal(q(1), q(2), q(3), q(4));
            phi = atan2(2*(w*x + y*z), 1 - 2*(x^2 + y^2));
            theta = asin(min(max(2*(w*y - z*x), -1), 1));
            psi = atan2(2*(w*z + x*y), 1 - 2*(y^2 + z^2));
        end

        function R = toDcm(q)
            %TODCM Body-to-world rotation matrix.
            q = dlab.physics.Quaternion.normalize(q);
            [w, x, y, z] = deal(q(1), q(2), q(3), q(4));
            R = [1 - 2*(y^2 + z^2), 2*(x*y - w*z),     2*(x*z + w*y)
                 2*(x*y + w*z),     1 - 2*(x^2 + z^2), 2*(y*z - w*x)
                 2*(x*z - w*y),     2*(y*z + w*x),     1 - 2*(x^2 + y^2)];
        end

        function q = multiply(a, b)
            %MULTIPLY Hamilton product a ⊗ b (apply b, then a).
            q = [a(1)*b(1) - a(2:4).' * b(2:4)
                 a(1)*b(2:4) + b(1)*a(2:4) + cross(a(2:4), b(2:4))];
        end

        function q = conjugate(q)
            %CONJUGATE The inverse rotation of a unit quaternion.
            q = [q(1); -q(2:4)];
        end

        function qe = relative(qRef, q)
            %RELATIVE Error quaternion qRef⁻¹ ⊗ q: the rotation from qRef
            %   to q, in qRef's body axes. Not sign-fixed: qe and −qe are
            %   the same rotation, and qe(1) < 0 is the long way round.
            qe = dlab.physics.Quaternion.multiply( ...
                dlab.physics.Quaternion.conjugate(qRef), q(:));
        end

        function q = fromDcm(R)
            %FROMDCM Quaternion of a body-to-world rotation matrix.
            %   Shepperd's method: of the four ways to recover it, the one
            %   with the largest divisor is the accurate one. The sign is
            %   whichever that way gives (q and −q are the same rotation).
            t = R(1, 1) + R(2, 2) + R(3, 3);
            if t > 0
                S = 2 * sqrt(t + 1);
                q = [S / 4; (R(3, 2) - R(2, 3)) / S; (R(1, 3) - R(3, 1)) / S; (R(2, 1) - R(1, 2)) / S];
            elseif R(1, 1) > R(2, 2) && R(1, 1) > R(3, 3)
                S = 2 * sqrt(1 + R(1, 1) - R(2, 2) - R(3, 3));
                q = [(R(3, 2) - R(2, 3)) / S; S / 4; (R(1, 2) + R(2, 1)) / S; (R(1, 3) + R(3, 1)) / S];
            elseif R(2, 2) > R(3, 3)
                S = 2 * sqrt(1 + R(2, 2) - R(1, 1) - R(3, 3));
                q = [(R(1, 3) - R(3, 1)) / S; (R(1, 2) + R(2, 1)) / S; S / 4; (R(2, 3) + R(3, 2)) / S];
            else
                S = 2 * sqrt(1 + R(3, 3) - R(1, 1) - R(2, 2));
                q = [(R(2, 1) - R(1, 2)) / S; (R(1, 3) + R(3, 1)) / S; (R(2, 3) + R(3, 2)) / S; S / 4];
            end
        end

        function dq = derivative(q, omega)
            %DERIVATIVE dq/dt for body angular rates OMEGA = [p; q; r] (rad/s).
            dq = 0.5 * dlab.physics.Quaternion.multiply(q(:), [0; omega(:)]);
        end

        function q = normalize(q)
            q = q(:) / norm(q);
        end

        function v = rotate(q, v)
            %ROTATE Body vector V expressed in the world frame.
            v = dlab.physics.Quaternion.toDcm(q) * v(:);
        end
    end
end
