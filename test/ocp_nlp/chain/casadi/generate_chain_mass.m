clc;
clear all;
close all;

addpath('../../casadi-octave-v3.1.1')
import casadi.*
mkdir('chain');

% Get collocation points
d = 3;
method = '';
Ns = 1; % NUMBER OF INTEGRATION STEPS

SOLVE = 1;

resX = []; resU = [];
for Nm = 2:5
    disp(['---- Nm value = ' num2str(Nm) '----']);

% Environment
g = 9.81;     % [N/kg]
L = 0.033;
D = 1.0;
m = 0.03;
x0 = zeros(3,1);
xN = [1 0 0].';

wall_pos = -0.01;

T = 5.0;
N = 20;

% Number of variables
nx = (Nm-1)*2*3;
nu = 3;

% State variables
u = SX.sym('u',3);
dae.p = u;

dae.x = [];
states = [];
for i = 1:Nm-1
    p = SX.sym(['p' num2str(i)],3);
    v = SX.sym(['v' num2str(i)],3);

    x_struct = struct('p',p,'v',v);
    states = [states; x_struct];
    dae.x = [dae.x; casadi_struct2vec(x_struct)];
end

% Compute forces
F = {};
for i = 1:Nm-1
    if i == 1
        dist = states(1).p-x0;
    else
        dist = states(i).p-states(i-1).p;
    end
    tmp = D*(1 - L/sqrt(dist.'*dist));
    F = {F{:}, tmp*dist};
end

% Set up ODE
dae.ode = [];
for i = 1:Nm-2
    f = 1/m*(F{i+1} - F{i}) - [0;0;g];
    dae.ode = [dae.ode; casadi_vec(x_struct,'p',states(i).v,'v',f)];
end
dae.ode = [dae.ode; casadi_vec(x_struct,'p',states(end).v,'v',u)];

tau_root = collocation_points(d,'legendre');

collfun = simpleColl(dae,tau_root,T/(Ns*N));
collfun = collfun.expand();

%% Find rest position
Xpoints = linspace(0,1,Nm);
x0_guess = [Xpoints(2:end);zeros(5,Nm-1)];
x0_guess = x0_guess(:);
u_guess = zeros(3,1);

odeFun = Function(['ode_chain_nm' num2str(Nm)],{dae.x,dae.p},{dae.ode,jacobian(dae.ode,[dae.x;dae.p])+SX.zeros(nx,nx+nu)});

Sx = SX.sym('Sx',nx,nx);
Sp = SX.sym('Sp',nx,nu);

vdeX = SX.zeros(nx,nx);
vdeX = vdeX + jtimes(dae.ode,dae.x,Sx);

vdeP = SX.zeros(nx,nu) + jacobian(dae.ode,dae.p);
vdeP = vdeP + jtimes(dae.ode,dae.x,Sp);

vdeFun = Function(['vde_chain_nm' num2str(Nm)],{dae.x,Sx,Sp,dae.p},{dae.ode,vdeX,vdeP});

jacX = SX.zeros(nx,nx) + jacobian(dae.ode,dae.x);
jacFun = Function(['jac_chain_nm' num2str(Nm)],{dae.x,dae.p},{dae.ode,jacX});

opts = struct('mex', false);
vdeFun.generate(['vde_chain_nm' num2str(Nm)], opts);
jacFun.generate(['jac_chain_nm' num2str(Nm)], opts);

val = odeFun(x0_guess,u_guess);
while norm(full(val)) > 1e-10
    [val,jac] = odeFun(x0_guess,u_guess);
    jac = full(jac); val = full(val);
    delta = -jac\val;
    x0_guess = x0_guess + delta(1:nx);
end
% x0_guess
xN_term = x0_guess;
err_rest = norm(full(val))

x0_mat2 = [zeros(6,1) reshape(x0_guess,6,Nm-1)];

Ypoints = linspace(0,1.5,Nm);
Zpoints = linspace(0,0.5,Nm);

x0_init = [zeros(1,Nm-1);Ypoints(2:end);Zpoints(2:end);zeros(3,Nm-1)];
x0_init = x0_init(:);
u_init = zeros(3,1);

val = odeFun(x0_init,u_init);
while norm(full(val)) > 1e-10
    [val,jac] = odeFun(x0_init,u_init);
    jac = full(jac); val = full(val);
    delta = -jac\val;
    x0_init = x0_init + delta(1:nx);
end
% x0_init
err_rest = norm(full(val))

save(['chain/x0_nm' num2str(Nm) '.dat'], 'x0_init', '-ascii', '-double');
save(['chain/xN_nm' num2str(Nm) '.dat'], 'xN_term', '-ascii', '-double');

x0_mat = [zeros(6,1) reshape(x0_init,6,Nm-1)];

Fontsize = 20;
set(0,'DefaultAxesFontSize',Fontsize)

%figure(1); set(gcf, 'Color','white');
%plot3(x0_mat2(1,:), x0_mat2(2,:), x0_mat2(3,:), '--ro', 'MarkerSize', 10); hold on;
%plot3(x0_mat(1,:), x0_mat(2,:), x0_mat(3,:), '--bo', 'MarkerSize', 10);
%p = patch([0, 1, 1, 0], [wall_pos, wall_pos, wall_pos, wall_pos], [-4, -4, 1, 1], 'g');
%xlabel( 'x [m]');
%ylabel( 'y [m]');
%zlabel( 'z [m]');
%xlim([0 1]);
%ylim([-0.1 2]);
%zlim([-4 1]);
%title('Initial and reference point');
%legend('reference', 'initial','wall')
%view([145 25]);
%grid on;
%% set(gca, 'Box', 'on');
%% pause

%x0 = [repmat([x0_guess;zeros(nx*Ns*d,1);u_guess],N,1);x0_guess];
% load(['../data_ME_' num2str(Nm) method '.mat'],'res');
% x0 = res;

 x0 = [];
 for k = 1:N
 %     x0 = [x0;repmat(resX(:,k),Ns*d+1,1);resU(:,k)];
     x0 = [x0;repmat(x0_guess,Ns*d+1,1);zeros(nu,1)];
 end
 % x0 = [x0;resX(:,N+1)];
 x0 = [x0;x0_guess];

if SOLVE

for rho = [0]
% for rho = [0.9 0.5 0.25 0]
    disp(['-- rho value = ' num2str(rho) '--']);


%% Optimal Control Problem
Xs = {};
for i=1:N+1
   Xs{i} = MX.sym(['X_' num2str(i)],nx);
end
XCs = {};
Us = {};
for i=1:N
   XCs{i} = MX.sym(['XC_' num2str(i)],nx,Ns*d);
   Us{i}  = MX.sym(['U_' num2str(i)],nu);
end

V_block = struct();
V_block.X  = Sparsity.dense(nx,1);
V_block.XC  = Sparsity.dense(nx,Ns*d);
V_block.U  = Sparsity.dense(nu,1);

% Simple bounds on states
lbx = {};
ubx = {};

% List of constraints
g = {};

% List of all decision variables (determines ordering)
V = {};
for k=1:N
  % Add decision variables
  V = {V{:} casadi_vec(V_block,'X',Xs{k},'XC',XCs{k},'U',Us{k})};
  
  if k==1
    % Bounds at t=0
    x_lb = x0_init;
    x_ub = x0_init;
    u_lb = -10*ones(3,1);
    u_ub = 10*ones(3,1);
    lbx = {lbx{:} casadi_vec(V_block,-inf,'X',x_lb,'U',u_lb)};
    ubx = {ubx{:} casadi_vec(V_block,inf, 'X',x_ub,'U',u_ub)};
  else %k < N
    % Bounds for other t
    m_lb  = [-inf;wall_pos;-inf;-inf;-inf;-inf];
    m_ub  = [inf;inf;inf;inf;inf;inf];
    x_lb = repmat(m_lb,Nm-1,1);
    x_ub = repmat(m_ub,Nm-1,1);
    u_lb = -10*ones(3,1);
    u_ub = 10*ones(3,1);
    lbx = {lbx{:} casadi_vec(V_block,-inf,'X',x_lb,'U',u_lb)};
    ubx = {ubx{:} casadi_vec(V_block,inf, 'X',x_ub,'U',u_ub)};
  end
  % Obtain collocation expressions
  Xcur = Xs{k};
  for i = 1:Ns
    [Xcur,coll_out] = collfun(Xcur,XCs{k}(:,1+(i-1)*d:i*d),Us{k});
    g = {g{:} coll_out};         % collocation constraints
  end
  g = {g{:} Xs{k+1}-Xcur}; % gap closing
end
  
V = {V{:} Xs{end}};

% Bounds for final t
x_lb = (1-rho)*xN_term+rho*x0_init;
x_ub = (1-rho)*xN_term+rho*x0_init;
lbx = {lbx{:} x_lb};
ubx = {ubx{:} x_ub};

% Objective function
% fun_ref = (vertcat(Xs{:})-repmat(xN_term,N+1,1));
controls = vertcat(Us{:});
effort = 1/2*controls.'*controls;

nlp = struct('x',vertcat(V{:}), 'f',effort, 'g', vertcat(g{:}));

nlpfun = Function('nlp',nlp,char('x','p'),char('f','g'));

%opts.ipopt = struct('linear_solver','ma27','acceptable_tol', 1e-12, 'tol', 1e-12);
solver = nlpsol('solver','ipopt',nlp);

%args = struct;
%args.x0 = x0;
%args.lbx = vertcat(lbx{:});
%args.ubx = vertcat(ubx{:});
%args.lbg = 0;
%args.ubg = 0;

res = solver('x0',x0,'lbx',vertcat(lbx{:}),'ubx',vertcat(ubx{:}),'lbg',0,'ubg',0);

x0 = full(res.x);
struct_res = res;

mu = [];
for k = 1:N
   mu = [mu; full(res.lam_g((k-1)*(Ns*nx*d+nx)+1:(k-1)*(Ns*nx*d+nx)+Ns*nx*d))]; 
end
lam = [];
for k = 1:N
   lam = [lam; full(res.lam_g((k-1)*(Ns*nx*d+nx)+Ns*nx*d+1:k*(Ns*nx*d+nx)))]; 
end

dim = size(casadi_struct2vec(V_block));
res_split = vertsplit(res.x,dim(1));

res_U = {}; resK = [];
for r=res_split(1:end-1)
    rs = casadi_vec2struct(V_block,r{1});
    res_U = {res_U{:} rs.U};
    
    k_mat = full(rs.XC);
    for i = 1:Ns
        resK = [resK; k_mat(:,1+(i-1)*d:i*d)];
    end
end

res_X = {};
for r=res_split(1:end-1)
    rs = casadi_vec2struct(V_block,r{1});
    res_X = {res_X{:} rs.X};
end
res_X = {res_X{:} res_split{end}};

%% Visualization solution
%figure(2); set(gcf, 'Color','white');
%plot3(x0_mat2(1,:), x0_mat2(2,:), x0_mat2(3,:), '--ro', 'MarkerSize', 14); hold on;
%plot3(x0_mat(1,:), x0_mat(2,:), x0_mat(3,:), '--bo', 'MarkerSize', 14);
%p = patch([0, 1, 1, 0], [wall_pos, wall_pos, wall_pos, wall_pos], [-4, -4, 1, 1], 'g');
%for k = 1:N+1
%    x_mat = [zeros(6,1) reshape(full(res_X{k}),6,Nm-1)];
%    plot3(x_mat(1,:), x_mat(2,:), x_mat(3,:), ':k+', 'MarkerSize', 6);
%end
%xlabel( 'x [m]');
%ylabel( 'y [m]');
%zlabel( 'z [m]');
%xlim([0 1]);
%ylim([-0.1 2]);
%zlim([-4 1]);
%title('Initial and reference point');
%legend('reference','initial','wall','solution')
%view([145 25]);
%grid on;
%% set(gca, 'Box', 'on');

resX = vertcat(res_X{:});
resX = full(reshape(resX,nx,N+1))

resU = vertcat(res_U{:});
resU = full(reshape(resU,nu,N))

res = full(res.x);

%if rho == 0
%    save(['../data_ME_' num2str(Nm) method '.mat'],'x0_init','xN_term','resX','resU','resK','res','lam','mu');
%end


save(['chain/resX_nm' num2str(Nm) '.dat'], 'resX', '-ascii', '-double');
save(['chain/resU_nm' num2str(Nm) '.dat'], 'resU', '-ascii', '-double');

end
end
end
