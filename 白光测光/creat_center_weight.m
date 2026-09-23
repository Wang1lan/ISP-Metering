%% lamda1和lamda2控制椭圆形状，miu1控制上下移动，miu2控制水平移动
lamda1 = 18;                      % 垂直方向变长      
lamda2 = 30;                      % 水平方向变长     
%%
miu1 = 67/2;                      % 垂直方向移动
miu2 = 120/2;                     % 水平方向移动
z = zeros(64,120);
txt = cell(8040,1);
for i = 1:67
    for j = 1:120
        z1 = (((i - miu1).^2) / (lamda1^2))   +   (((j - miu2).^2) / (lamda2^2));
        z(i,j) = (exp(-0.5*z1));    
    end
end
max_z = max(max(z));z = double(z.*(255/max_z));
figure(1);imshow(uint8(z));

for i = 1:67
    for j = 1:120
        if z(i,j)>=0 && z(i,j)<=28.3
            txt((i-1)*120+j,1) = {'0'};   % 这里判断每个权重的等级，将所有等级分为0-8，方便计数
        elseif z(i,j)>28.3 && z(i,j)<=56.6
            txt((i-1)*120+j,1) = {'1'};
        elseif z(i,j)>56.6 && z(i,j)<=84.9
            txt((i-1)*120+j,1) = {'2'};
        elseif z(i,j)>84.9 && z(i,j)<=113.2
            txt((i-1)*120+j,1) = {'3'};
        elseif z(i,j)>113.2 && z(i,j)<=141.5
            txt((i-1)*120+j,1) = {'4'};
        elseif z(i,j)>141.5 && z(i,j)<=169.8
            txt((i-1)*120+j,1) = {'5'};
        elseif z(i,j)>169.8 && z(i,j)<=198.1
            txt((i-1)*120+j,1) = {'6'};
        elseif z(i,j)>198.1 && z(i,j)<=226.4
            txt((i-1)*120+j,1) = {'7'};
        elseif z(i,j)>226.4 && z(i,j)<=255
            txt((i-1)*120+j,1) = {'8'};   
        end
    end
end
txt = str2num(cell2mat(txt));

%% 下发给算法使用的权重文件
fid = fopen('算法_中心.txt','wt');
fprintf(fid,'%d\n',txt);
fclose(fid);

% %% 下发给FPGA使用的权重文件
% Center = load(name);
% name_1=['FPGA_8_',num2str(lamda1),'_',num2str(lamda2),'.txt'];
% fid1 = fopen(name_1,'w');
% for k = 1:8040
%     % fprintf(fid1,'%d',k-1); 
%     % fprintf(fid1,'%s',":");
%     fprintf(fid1,'%d\n',Center(k));
% end
% fclose(fid1);