%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%      DDP Inverted Pendelum       %%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%  Course: Robotics and Autonomy   %%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%  AE8803  Spring  2020            %%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%  Author: Alejandro Escontrela    %%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear all;
close all;


global m1;
global I1;
global b1;
global g;
global l1;

% Environment parameters.
m1 = 1.4; % Link mass in Kg.
g = 9.8; % Gravity in m/s^2.
b1 = 0; % Friction coefficient.
l1 = 0.3; % Link length in meters.
I1 = m1 * l1^2; % Inertia in Kg*m^2.

% Solver parameters.
Horizon = 300; % Time Horizon.
num_iter = 50; % Number of Iterations
dt = 0.01; % Discretization.

% Costs.
Q_f = zeros(2,2); % State cost. 2x2 since state is 2-dimensional.
Q_f(1,1) = 100;
Q_f(2,2) = 100;

R = 10 * eye(1,1); % Control cost. 1x1 since control is 1-dimensional.

% Initialize solution.
xo = zeros(2,1);
xo(1,1) = 0; % Initial theta.
xo(2,1) = 0; % Initial theta_dot.

u_k = zeros(1,Horizon-1); % Initial control.
du_k = zeros(1,Horizon-1); % Initial control variation.

x_traj = zeros(2,Horizon); % Initial trajectory.

% Target:
p_target(1,1) = pi; % Target theta.
p_target(2,1) = 0; % Target theta_dot.

% Learning Rate
gamma = 0.5;

for k = 1:num_iter
    for  j = 1:(Horizon-1)    
        [l0,l_x,l_xx,l_u,l_uu,l_ux] = fnCost(x_traj(:,j), u_k(:,j), j,R,dt);
        % Compute loss function gradients for the current timestep.
        % Quadratic Approximations of the cost function.
        q0(j) = dt * l0; % L.
        q_k(:,j) = dt * l_x; % Lx.
        Q_k(:,:,j) = dt * l_xx; % Lxx.
        r_k(:,j) = dt * l_u; % Lu.
        R_k(:,:,j) = dt * l_uu; % Luu.
        P_k(:,:,j) = dt * l_ux; % Lux.

        % Linearize the dynamics using first order taylor expansion.
        [Fx,Fu] = fnState_And_Control_Transition_Matrices(x_traj(:,j),u_k(:,j),du_k(:,j),dt);
        A(:,:,j) = eye(2,2) + Fx * dt;
        B(:,:,j) = Fu * dt;  
    end

    % Compute value function at final timestep, its gradient, and its jacobian.
    Vxx(:,:,Horizon)= Q_f;
    Vx(:,Horizon) = Q_f * (x_traj(:,Horizon) - p_target); 
    V(Horizon) = 0.5 * (x_traj(:,Horizon) - p_target)' * Q_f * (x_traj(:,Horizon) - p_target); 

    % Backpropagation of the Value Function.
    for j = (Horizon-1):-1:1
        % Quu = Luu + B^T * Vxx * B
        H = R_k(:,:,j) + B(:,:,j)' * Vxx(:,:,j+1) * B(:,:,j);
        % Qux = Lux + B^T * Vxx * A
        G = P_k(:,:,j) + B(:,:,j)' * Vxx(:,:,j+1) * A(:,:,j);
        % Qu = Lu + B^T * Vx
        g_ = r_k(:,j) +  B(:,:,j)' * Vx(:,j+1);


        inv_H = inv(H); % Quu^-1
        L_k(:,:,j)= - inv_H * G; % Feedback term = -Quu^-1 * Qux.
        l_k (:,j) = - inv_H *g_; % Feedforward term = -Quu^-1 * Qu.

        % Vxx = (Lxx + A^T * Vxx * A) + (-Qxu * Quu^-1) * Quu * (-Quu^-1 * Qux)
        % + (-Qxu * Quu^-1 * Qux) + (Qxu * -Quu^-1 * Qux) 
        Vxx(:,:,j) = Q_k(:,:,j)+ A(:,:,j)' * Vxx(:,:,j+1) * A(:,:,j) + L_k(:,:,j)' * H * L_k(:,:,j) + L_k(:,:,j)' * G + G' * L_k(:,:,j);
        % Vx = (Lx + A^T * Vx') + (-Qxu * Quu^-1 * Qu) + (Qxu * -Quu^-1 * Qu) +
        % (-Qxu * Quu^-1 * Qu * Quu * -Quu^-1 * Qu)
        Vx(:,j)= q_k(:,j) +  A(:,:,j)' *  Vx(:,j+1) + L_k(:,:,j)' * g_ + G' * l_k(:,j) + L_k(:,:,j)'*H * l_k(:,j);
        % V = L + V' + (0.5 * Qu^T * Quu^-1 * Quu * Quu^-1 * Qu) + (-Qu^T * Quu^-1 * Qu)
        V(:,j) = q0(j) + V(j+1) + 0.5 *  l_k (:,j)' * H * l_k (:,j) + l_k (:,j)' * g_;
    end

    % Find the controls.
    dx = zeros(2,1);
    for i=1:(Horizon-1)    
        du = l_k(:,i) + L_k(:,:,i) * dx;
        dx = A(:,:,i) * dx + B(:,:,i) * du;  
        u_new(:,i) = u_k(:,i) + gamma * du;
    end

    u_k = u_new;

    % Create new rollout.
    [x_traj] = fnSimulate(xo,u_new,Horizon,dt,0);
    [Cost(:,k)] =  fnCostComputation(x_traj,u_k,p_target,dt,Q_f,R);
    x1(k,:) = x_traj(1,:);

    if mod(k, 10) == 0
        fprintf('iLQG Iteration %d,  Current Cost = %e \n',k,Cost(1,k));
    end
end


time(1)=0;
for i= 2:Horizon
    time(i) =time(i-1) + dt;  
end

visualize;
close(fh);