%%% process the robot sensor and pose data

%% %%%%%%%%%%%%%%%%%%%%%% MobileSim analysis
%{
addpath('/Users/changliu/Documents/Git/Autonomous_agent_search/multi_agent_search/experiment/data');
clear;
% choose the robot data
r_idx = 2;
if (r_idx == 1)
    r_prefix = 'r1';
elseif (r_idx == 2)
    r_prefix = 'r2';
end
%% Sonar
% read sonar reading from csv file
[data_s,~] = readtext(sprintf('%s_sonar_mobilesim_010416.csv',r_prefix));
sonar_rd = struct();
sonar_rd.time = [data_s{2:end,1}]'; % this time seems to be the epoch time
sonar_rd.stamp = [data_s{2:end,3}]'; % don't understand why stamp is different from time

% convert from epoch time to human-readable time
sonar_rd.time = sonar_rd.time * 1e-9;% # of seconds since 1970.1.1 0h 0m 0s. The original time is in nano-second.
% epoch time -> MATLAB datenum
dnum = datenum(1970,1,1,0,0,sonar_rd.time);
% split time into parts
[Y, M, D, H, MN, S] = datevec(dnum);

sonar_rd.stamp = sonar_rd.stamp * 1e-9;
% epoch time -> MATLAB datenum
dnum2 = datenum(1970,1,1,0,0,sonar_rd.stamp);
% split time into parts
[Y2, M2, D2, H2, MN2, S2] = datevec(dnum2);
sonar_rd.sec_time = H2*3600+MN2*60+S2;% this is the time in seconds taking into account hour, min and second. not starting from 1970 but current day.

sonar_rd.pts = zeros(size(data_s,1)-1,16);
% read readings from 8 front sonars
for ii = 1:8
    sonar_rd.pts(:,2*(ii-1)+1) = [data_s{2:end,3*(ii-1)+5}];
    sonar_rd.pts(:,2*ii) = [data_s{2:end,3*(ii-1)+6}];
end

%% Pose
% read pose reading from csv file
[data_p,~] = readtext(sprintf('%s_pose_mobilesim_010416.csv',r_prefix));
pose_rd = struct();
pose_rd.time = [data_p{2:end,1}]'; % this time seems to be the epoch time
pose_rd.stamp = [data_p{2:end,3}]'; % don't understand why stamp is different from time

% convert from epoch time to human-readable time
pose_rd.time = pose_rd.time * 1e-9;% # of seconds since 1970.1.1 0h 0m 0s
% epoch time -> MATLAB datenum
dnum3 = datenum(1970,1,1,0,0,pose_rd.time);
% split time into parts
[Y3, M3, D3, H3, MN3, S3] = datevec(dnum3);

pose_rd.stamp = pose_rd.stamp * 1e-9;
% epoch time -> MATLAB datenum
dnum4 = datenum(1970,1,1,0,0,pose_rd.stamp);
% split time into parts
[Y4, M4, D4, H4, MN4, S4] = datevec(dnum4);
pose_rd.sec_time = H4*3600+MN4*60+S4;% this is the time in seconds taking into account hour, min and second. not starting from 1970 but current day.

% position
[~,pos_x_idx] = ismember('field.pose.pose.position.x',data_p(1,:)); % position
[~,pos_y_idx] = ismember('field.pose.pose.position.y',data_p(1,:)); % position
% note: orientation takes quaternion format
[~,ori_x_idx] = ismember('field.pose.pose.orientation.x',data_p(1,:)); % orientation
[~,ori_y_idx] = ismember('field.pose.pose.orientation.y',data_p(1,:)); % orientation
[~,ori_z_idx] = ismember('field.pose.pose.orientation.z',data_p(1,:)); % orientation
[~,ori_w_idx] = ismember('field.pose.pose.orientation.w',data_p(1,:)); % orientation

% convert orientation to axis angle
qx = [data_p{2:end,ori_x_idx}]';
qy = [data_p{2:end,ori_y_idx}]';
qw = [data_p{2:end,ori_w_idx}]';
qz = [data_p{2:end,ori_z_idx}]';
% ori = 2*acos(qw);
% ori_deg = ori/pi*180;
% z = [data_p{2:end,pos_z_idx}]./sqrt(1-qw.*qw);

% convert orientation to Euler angle
% phi = atan2(2*(qw.*qx+qy.*qz),1-2*(qx.^2+qy.^2)); % row
% theta = asin(2*(qw.*qy-qz.*qx)); % pitch
psi = atan2(2*(qw.*qz+qx.*qy),1-2*(qy.^2+qz.^2)); % yaw
ltzero_idx = (psi < 0);
psi(ltzero_idx) = psi(ltzero_idx)+2*pi;
psi_deg = psi/pi*180;

% velocity
[~,vel_x_idx] = ismember('field.twist.twist.linear.x',data_p(1,:)); % linear velocity
[~,vel_y_idx] = ismember('field.twist.twist.linear.y',data_p(1,:)); % linear velocity
[~,vel_z_idx] = ismember('field.twist.twist.angular.z',data_p(1,:)); % angular velocity

% read pose readings
% poses in data_p assumes the initial position of robot as (0,0,0), adding
% the home position to data_p to get state in global coordinate.
if (r_idx == 1)
    init_pos = [2;2;0];
elseif (r_idx == 2)
    init_pos = [18;13;0];
end

pose_rd.pos = bsxfun(@plus,[[data_p{2:end,pos_x_idx}];[data_p{2:end,pos_y_idx}];psi'],init_pos); % [pos_x;pos_y;orientation]
pose_rd.vel = [[data_p{2:end,vel_x_idx}];[data_p{2:end,vel_y_idx}];[data_p{2:end,vel_z_idx}]]; %[v_x;v_y;v_angular];

%% Compute object distance
% compute measured distance
num = length(pose_rd.time); % number of readings
sonar_ori = [90,50,30,10,-10,-30,-50,-90]/180*pi;
obj_pos = zeros(2*num,8); % there are 8 sonar readings [x1;y1;x2;y2;...;x8;y8]
obj_dist = zeros(num,8); % there are 8 sonar readings [dis1,...,dis8]
obj_ori = zeros(num,8); % orientation relative to robot local cooridnate
for ii = 1:num
%     obj_pos(2*(ii-1)+1:2*ii,:) = bsxfun(@plus, reshape(sonar_rd.pts(ii,:),2,8),pose_rd.pos(1:2,ii));
%     obj_dist(ii,:) = sqrt(sum(reshape(sonar_rd.pts(ii,:),2,8).^2,1));
    tmp_loc_pos = reshape(sonar_rd.pts(ii,:),2,8); % convert the local coordinate into 2*8 format instead of 1*16 format
    obj_pos(2*(ii-1)+1:2*ii,:) = tmp_loc_pos;
    obj_dist(ii,:) = sqrt(sum(tmp_loc_pos.^2,1));
    obj_ori(ii,:) = atan2(tmp_loc_pos(2,:),tmp_loc_pos(1,:));
end

% visualize the detected position
% plot(obj_pos(1:2:2*num-1,5),obj_pos(2:2:2*num,5));
    
% wall coordinates: when a measurement is close in x or y coordinates to
% the ones saved here, it is considered as a measurement of walls
wall_x = [0,20];
wall_y = [0,15];
thrd = 0.3; % threshold for deciding if two values match

% retrieve target measurement
sonar_idx = 4; % retrieve a single sonar first
% 1. remove measurements whose reading distance is greater than 5.1m (max distance is 5.162m)
dis_thrd = 5.1; % threshold for deciding whether maximum distance is returned
log_idx = (obj_dist(:,sonar_idx) <= dis_thrd); % logical indices for measurements that detect an object
tmp_idx = (1:num)';
tmp_idx(log_idx == 0) = [];

% 2. remove measurements from walls
% positions of object in global coordinate
tmp_glb_pos = zeros(2*length(tmp_idx),1);
tmp_idx2 = [];
for jj = 1:length(tmp_idx)
    % quantities in local coordinate
    tmp_obj_dist = obj_dist(tmp_idx(jj),sonar_idx); % distance between sonar and object
    tmp_loc_ori = obj_ori(tmp_idx(jj),sonar_idx); % local orientation from sonar and object
    
    % orientation of object in global coordinate    
    tmp_glb_ori = pose_rd.pos(3,tmp_idx(jj))+tmp_loc_ori;
    tmp_glb_pos(2*(jj-1)+1:2*jj) = pose_rd.pos(1:2,tmp_idx(jj))+tmp_obj_dist*[cos(tmp_glb_ori);sin(tmp_glb_ori)];
    
    if (abs(tmp_glb_pos(2*(jj-1)+1)-wall_x(1)) < thrd) || (abs(tmp_glb_pos(2*(jj-1)+1)-wall_x(2)) < thrd)...
            || (abs(tmp_glb_pos(2*jj)-wall_y(1)) < thrd) || (abs(tmp_glb_pos(2*jj)-wall_y(2)) < thrd)
        continue
    else
        tmp_idx2 = [tmp_idx2;jj];
    end
end
tar_idx = [2*(tmp_idx2-1)+1,2*tmp_idx2]';
tar_idx = tar_idx(:);
tar_pos = (reshape(tmp_glb_pos(tar_idx),2,length(tmp_idx2)))'; % retrieve the measurement for target

plot(tar_pos(:,1),tar_pos(:,2));

% full_obs = -1*ones(num,2); % full observed target position in global coordinate
% tmp_idx3 = (1:num)';
% tmp_idx3 = tmp_idx3(log_idx == 1);
% tmp_idx3 = tmp_idx3(tmp_idx2);
% full_obs(tmp_idx3,:) = tar_pos;

% save measured target position
% folder_path = '/Users/changliu/Documents/Git/Autonomous_agent_search/multi_agent_search/experiment/data';
% file_name = sprintf('%s_tar_pos_mobilesim_010416',r_prefix);
% save(fullfile(folder_path,file_name),'full_obs','pose_rd');

%}

%% %%%%%%%%%%%%%%%%%%%%%% experiment analysis
%% process experiment data
% this cell is from Jan 2016 experiment. will be modified for new experiment data
%{
% read sonar reading from csv file
addpath('/Users/changliu/Documents/Git/Multi_agent_search/experiment/data');
clear;
name_set = {'0dot5','1dot0','2dot0','3dot0','4dot0'};
nomi_dist = [0.5,1:4];% nominal distance
dataset_num = length(name_set);
sonar_m = zeros(2,dataset_num); % sonar mean for all dataset
sonar_cov = zeros(2*dataset_num,2); % sonar covariance for all dataset
sonar_offset_m = zeros(2,dataset_num); % sonar offset mean for all dataset
sonar_offset_cov = zeros(2*dataset_num,2); % sonar offset covariance for all dataset

for jj = 5%1:dataset_num
    [data_s,~] = readtext(sprintf('sonar_exp_010916_%s.csv',name_set{jj}));
    sonar_rd = struct();
    sonar_rd.time = [data_s{2:end,1}]'; % this time seems to be the epoch time
    sonar_rd.stamp = [data_s{2:end,3}]'; % don't understand why stamp is different from time
    
    % convert from epoch time to human-readable time
    sonar_rd.time = sonar_rd.time * 1e-9;% # of seconds since 1970.1.1 0h 0m 0s. The original time is in nano-second.
    % epoch time -> MATLAB datenum
    dnum = datenum(1970,1,1,0,0,sonar_rd.time);
    % split time into parts
    [Y, M, D, H, MN, S] = datevec(dnum);
    
    sonar_rd.stamp = sonar_rd.stamp * 1e-9;
    % epoch time -> MATLAB datenum
    dnum2 = datenum(1970,1,1,0,0,sonar_rd.stamp);
    % split time into parts
    [Y2, M2, D2, H2, MN2, S2] = datevec(dnum2);
    sonar_rd.sec_time = H2*3600+MN2*60+S2;% this is the time in seconds taking into account hour, min and second. not starting from 1970 but current day.
    
    sonar_rd.pts = zeros(size(data_s,1)-1,16);
    % read readings from 8 front sonars
    for ii = 1:8
        sonar_rd.pts(:,2*(ii-1)+1) = [data_s{2:end,3*(ii-1)+5}];
        sonar_rd.pts(:,2*ii) = [data_s{2:end,3*(ii-1)+6}];
    end
    
    % Compute object distance
    % compute measured distance
    num = length(sonar_rd.time); % number of readings
    sonar_ori = [90,50,30,10,-10,-30,-50,-90]/180*pi;
    obj_pos = zeros(2*num,8); % there are 8 sonar readings [x1;y1;x2;y2;...;x8;y8]
    offset_pos = zeros(size(obj_pos)); % offset of coordinates based on nominal distance
    obj_dist = zeros(num,8); % there are 8 sonar readings [dis1,...,dis8]
    obj_ori = zeros(num,8); % orientation relative to robot local cooridnate
    for ii = 1:num
        tmp_loc_pos = reshape(sonar_rd.pts(ii,:),2,8); % convert the local coordinate into 2*8 format instead of 1*16 format
        obj_pos(2*(ii-1)+1:2*ii,:) = tmp_loc_pos;
        obj_dist(ii,:) = sqrt(sum(tmp_loc_pos.^2,1));
        obj_ori(ii,:) = atan2(tmp_loc_pos(2,:),tmp_loc_pos(1,:)); % check if this is close to 0 deg
        offset_pos(2*(ii-1)+1:2*ii,:) = obj_pos(2*(ii-1)+1:2*ii,:)-nomi_dist(jj)*[cos(obj_ori(ii,:));sin(obj_ori(ii,:))];
    end
    
    % MLE of bivariate Normal
    sonar_idx = 4;
    tmp_pos = (reshape(obj_pos(:,sonar_idx),2,num))';
    tmp_offset = (reshape(offset_pos(:,sonar_idx),2,num))';
    sonar_m(:,jj) = (mean(tmp_pos))';
    sonar_cov(2*(jj-1)+1:2*jj,:) = cov(tmp_pos);
    sonar_offset_m(:,jj) = (mean(tmp_offset))';
    sonar_offset_cov(2*(jj-1)+1:2*jj,:) = cov(tmp_offset);
    
    % draw offset plots
    figure(1)
%     hold on
    color_set = {'r','g','b','m','c'};
    plot3(tmp_pos(:,1),tmp_pos(:,2),1:size(tmp_pos,1),color_set{1});
    figure(2)
    plot3(tmp_offset(:,1),tmp_offset(:,2),1:size(tmp_offset,1),color_set{jj});
    figure(3)
    plot(tmp_offset(:,1),tmp_offset(:,2),color_set{jj});
end
% legend('0.5','1','2','3','4');
%}

%% %%%%%%%%%%%%%%%%%%%%%% experiment analysis -- sonar modeling
% this cell analyzes the experiment data from Oct 2016
%{
% read sonar reading from csv file
addpath('/Users/changliu/Documents/Git/Multi_agent_search/experiment/sonar_modeling_data/2016Oct/101216');
clear;
name_set = {'20inch','40inch','60inch','80inch','100inch','120inch','140inch','160inch','180inch'};
nomi_dist = (20:20:180)*2.54/100; % nominal distance (covert from inch to meter)
% name_set = {'0dot5','1dot0','2dot0','3dot0','4dot0'};
% nomi_dist = [0.5,1:4];
dataset_num = length(name_set);
sonar_m = zeros(2,dataset_num); % sonar mean for all dataset
sonar_cov = zeros(2*dataset_num,2); % sonar covariance for all dataset
sonar_offset_m = zeros(2,dataset_num); % sonar offset mean for all dataset
sonar_offset_cov = zeros(2*dataset_num,2); % sonar offset covariance for all dataset

mean_meas = zeros(length(name_set),1);
cov_meas = cell(length(name_set),1);

start_row = 4; % start recording the data from 4th row. 1st row is the header, 2nd-3rd row are usually data from last test
for jj = 1:dataset_num
%     [data_s,~] = readtext(sprintf('sonar_exp_101216_%s.csv',name_set{jj}));
    [data_s,~] = readtext(sprintf('101216_%s.csv',name_set{jj}));
    sonar_rd = struct();
    sonar_rd.time = [data_s{start_row:end,1}]'; % this time seems to be the epoch time
    sonar_rd.stamp = [data_s{start_row:end,3}]'; % don't understand why stamp is different from time
    
    % convert from epoch time to human-readable time
    sonar_rd.time = sonar_rd.time * 1e-9;% # of seconds since 1970.1.1 0h 0m 0s. The original time is in nano-second.
    % epoch time -> MATLAB datenum
    dnum = datenum(1970,1,1,0,0,sonar_rd.time);
    % split time into parts
    [Y, M, D, H, MN, S] = datevec(dnum);
    
    sonar_rd.stamp = sonar_rd.stamp * 1e-9;
    % epoch time -> MATLAB datenum
    dnum2 = datenum(1970,1,1,0,0,sonar_rd.stamp);
    % split time into parts
    [Y2, M2, D2, H2, MN2, S2] = datevec(dnum2);
    sonar_rd.sec_time = H2*3600+MN2*60+S2;% this is the time in seconds taking into account hour, min and second. not starting from 1970 but current day.
    
    sonar_rd.pts = zeros(size(data_s,1)-(start_row-1),16);
    % read readings from 8 front sonars
    for ii = 1:8
        sonar_rd.pts(:,2*(ii-1)+1) = [data_s{start_row:end,3*(ii-1)+5}];
        sonar_rd.pts(:,2*ii) = [data_s{start_row:end,3*(ii-1)+6}];
    end
    
    % Compute object distance
    % compute measured distance
    num = length(sonar_rd.time); % number of readings
%     sonar_ori = [90,50,30,10,-10,-30,-50,-90]/180*pi;
    obj_pos = zeros(2*num,8); % there are 8 sonar readings [x1;y1;x2;y2;...;x8;y8]
%     offset_pos = zeros(size(obj_pos)); % offset of coordinates based on nominal distance
    obj_dist = zeros(num,8); % there are 8 sonar readings [dis1,...,dis8]
%     obj_ori = zeros(num,8); % orientation relative to robot local cooridnate
    for ii = 1:num
        tmp_loc_pos = reshape(sonar_rd.pts(ii,:),2,8); % convert the local coordinate into 2*8 format instead of 1*16 format
        obj_pos(2*(ii-1)+1:2*ii,:) = tmp_loc_pos;
        obj_dist(ii,:) = sqrt(sum(tmp_loc_pos.^2,1));
%         obj_ori(ii,:) = atan2(tmp_loc_pos(2,:),tmp_loc_pos(1,:)); % check if this is close to 0 deg
%         offset_pos(2*(ii-1)+1:2*ii,:) = obj_pos(2*(ii-1)+1:2*ii,:)-nomi_dist(jj)*[cos(obj_ori(ii,:));sin(obj_ori(ii,:))];
    end
    
    sonar_idx = 4; % the sonar of interest
    meas_dist = obj_dist(:,sonar_idx);
    % data measured from 180inch contains some missing measurement, remove
    % them
    rmv_idx = meas_dist > 5.05;
    meas_dist(rmv_idx) = [];
    
    mean_meas(jj) = mean(meas_dist);
    cov_meas{jj} = std(meas_dist);    
end
% line fitting
X = [ones(length(nomi_dist),1),mean_meas];
y = nomi_dist';
B = X\y; % coefficient for linear fitting

% compare the fitting results
% figure
% hold on
% plot(X(:,2),y)
% plot(X(:,2),X*B)
% display(y-X*B)
%}

%% %%%%%%%%%%%%%%%%%%%%%  experiment analysis -- localization data interpretation
%
% addpath('/Users/changliu/Documents/Git/Multi_agent_search/experiment/localization');
clear;
% meas_data{1} is a N-by-4 matrix, first two columns correspond to robot
% position, third for orientation and last one for measured distance.
meas_data = cell(3,1);
all_name_set = {{'20inch','40inch','60inch','80inch','100inch','120inch','140inch','160inch','180inch'};...
    {'30inch','50inch','70inch','90inch','110inch'};...
    {'30inch','50inch','70inch','90inch','100inch'}};

all_r_state = {[123.5*ones(9,1)*2.54/100 (358-(210:-20:50))'*2.54/100 3*pi/2*ones(9,1)],...
    [(250.7-(30:20:110))'*2.54/100 124*ones(5,1)*2.54/100 pi*ones(5,1)],...
    [[(30:20:90)';100]*2.54/100 124.5*ones(5,1)*2.54/100 zeros(5,1)]};


for rbt_idx = 1:3
    % ind_meas_data is the individual robot's measurement data and its state
    ind_meas_data = zeros(0,4);

    name_set = all_name_set{rbt_idx};
%     nomi_dist = all_r_state*2.54/100; % nominal distance (covert from inch to meter)
    
    dataset_num = length(name_set);
    sonar_m = zeros(2,dataset_num); % sonar mean for all dataset
    sonar_cov = zeros(2*dataset_num,2); % sonar covariance for all dataset
    sonar_offset_m = zeros(2,dataset_num); % sonar offset mean for all dataset
    sonar_offset_cov = zeros(2*dataset_num,2); % sonar offset covariance for all dataset
    
    mean_meas = zeros(length(name_set),1);
    cov_meas = cell(length(name_set),1);
    
    start_row = 4; % start recording the data from 4th row. 1st row is the header, 2nd-3rd row are usually data from last test
    for jj = 1:dataset_num
        r_state = all_r_state{rbt_idx}(jj,:);
        
        [data_s,~] = readtext(sprintf('./localization/101216-side%d/101216_side%d_%s.csv',rbt_idx,rbt_idx,name_set{jj}));
        sonar_rd = struct();
        sonar_rd.time = [data_s{start_row:end,1}]'; % this time seems to be the epoch time
        sonar_rd.stamp = [data_s{start_row:end,3}]'; % don't understand why stamp is different from time
        
        % convert from epoch time to human-readable time
        sonar_rd.time = sonar_rd.time * 1e-9;% # of seconds since 1970.1.1 0h 0m 0s. The original time is in nano-second.
        % epoch time -> MATLAB datenum
        dnum = datenum(1970,1,1,0,0,sonar_rd.time);
        % split time into parts
        [Y, M, D, H, MN, S] = datevec(dnum);
        
        sonar_rd.stamp = sonar_rd.stamp * 1e-9;
        % epoch time -> MATLAB datenum
        dnum2 = datenum(1970,1,1,0,0,sonar_rd.stamp);
        % split time into parts
        [Y2, M2, D2, H2, MN2, S2] = datevec(dnum2);
        sonar_rd.sec_time = H2*3600+MN2*60+S2;% this is the time in seconds taking into account hour, min and second. not starting from 1970 but current day.
        
        sonar_rd.pts = zeros(size(data_s,1)-(start_row-1),16);
        % read readings from 8 front sonars
        for ii = 1:8
            sonar_rd.pts(:,2*(ii-1)+1) = [data_s{start_row:end,3*(ii-1)+5}];
            sonar_rd.pts(:,2*ii) = [data_s{start_row:end,3*(ii-1)+6}];
        end
        
        % Compute object distance
        % compute measured distance
        num = length(sonar_rd.time); % number of readings
        obj_pos = zeros(2*num,8); % there are 8 sonar readings [x1;y1;x2;y2;...;x8;y8]
        obj_dist = zeros(num,8); % there are 8 sonar readings [dis1,...,dis8]
        for ii = 1:num
            tmp_loc_pos = reshape(sonar_rd.pts(ii,:),2,8); % convert the local coordinate into 2*8 format instead of 1*16 format
            obj_pos(2*(ii-1)+1:2*ii,:) = tmp_loc_pos;
            obj_dist(ii,:) = sqrt(sum(tmp_loc_pos.^2,1));
        end
        
        sonar_idx = 4; % the sonar of interest
        meas_dist = obj_dist(:,sonar_idx);
        % data measured from 180inch contains some missing measurement, remove
        % them
        rmv_idx = meas_dist > 5.05;
        meas_dist(rmv_idx) = [];
        tmp_meas_data = [ones(length(meas_dist),1)*r_state,meas_dist];
        ind_meas_data = [ind_meas_data;tmp_meas_data];
    end
    
    meas_data{rbt_idx} = ind_meas_data;
end

save('./localization/exp_meas_data','meas_data')
%}