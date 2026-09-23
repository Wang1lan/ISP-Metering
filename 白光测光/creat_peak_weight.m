%lamda1和lamda2控制椭圆形状，miu1控制上下移动，miu2控制水平移动
lamda1 = 17;                        % 垂直方向变长
lamda2 = 30;                        % 水平方向变长
miu1 = 67/2;                        % 垂直方向移动
miu2 = 120/2;                       % 水平方向移动
z = zeros(67,120);
txt = cell(8040,1);
for i = 1:67
    for j = 1:120
        z1 = (((i - miu1).^2) / (lamda1^2))   +   (((j - miu2).^2) / (lamda2^2));
        z(i,j) = (exp(-0.5*z1));
        % 直接截断，取一个椭圆，椭圆由高斯生成的阈值作为边界，这里的阈值设定为0.5
        if  z(i,j)>0.5
             z(i,j) =  1;
        else
             z(i,j) = 0;
        end
    end
end
max_z = max(max(z));
z = double(z./max_z);%最大值为255
figure(1);imshow(uint8(z.*255));


right = zeros(8040,1);
for i = 1:67
    for j = 1:120
        right((i-1)*120+j,1) = z(i,j);
    end
end
%% 算法使用权重文件
fid = fopen('算法_峰值.txt','wt');
fprintf(fid,'%d\n',right);
fclose(fid);

% %% FPGA使用权重文件
% Peak = load(name);
% name=strcat('FPGA_peak_',num2str(lamda1),'_',num2str(lamda2),'.txt');
% fid1 = fopen(name,'w');
% for k = 1:8040
%     % fprintf(fid1,'%d',k-1); 
%     % fprintf(fid1,'%s',":");
%     fprintf(fid1,'%d\n',Peak(k));
%     % fprintf(fid1,'%s\n',",");
% end
% fclose(fid1);
