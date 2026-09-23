function output = center_test(input)
a = rgb2yuv(input,'BT709',8);
img = double(a(:,:,1));
[m,n] = size(img);                         
block_height = 16;
block_width = 16;
max = 2^8;

s = zeros(8040,1);
% weight1 = textread('算法_中心.txt','%s');

fileID = fopen('F:\isp\硬镜\白光测光算法\算法_中心.txt', 'r'); 
if fileID == -1
    error('无法打开文件，请检查路径是否包含特殊字符或文件是否被占用。');
end
weight = textscan(fileID, '%s');
fclose(fileID);
weight1 = weight{1}; % 提取出 cell 数组

index_1 = 0;
sn1 = 0; sn2 = 0; sn3 = 0; sn4 = 0; sn5 = 0; sn6 = 0; sn7 = 0; sn8 = 0; sn9 = 0;   % 相同权重的个数值
%% 对权重文件赋值
for x = 1:block_height:m-8  
    for y = 1:block_width:n  
        image_block = img(x:x+block_height-1,y:y+block_width-1);                   % 得到了每个图像块        
        image_value = fix(mean(mean(image_block)));                                % 得到了每个图像块的均值
        find = 120*index_1 +( (y+15)/16);                                           % 每个图像块对应的索引值
        
        if str2double(cell2mat(weight1(find))) == 0                                    
            w = 0*max;                    % 权重值
            sn1 = sn1+1;                  % 该权重使用的个数
            s(find,1) = image_value * w;  % 权重后的像素值
        elseif str2double(cell2mat(weight1(find))) == 1
            w = 0.125*max;
            sn2 = sn2+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 2
            w = 0.25*max;
            sn3 = sn3+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 3
            w = 0.375*max;
            sn4 = sn4+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 4
            w = 0.5*max;
            sn5 = sn5+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 5
            w = 0.625*max;
            sn6 = sn6+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 6
            w = 0.75*max;
            sn7 = sn7+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 7
            w = 0.875*max;
            sn8 = sn8+1;
            s(find,1) = image_value * w;
        elseif str2double(cell2mat(weight1(find))) == 8
            w = 1*max;
            sn9 = sn9+1;
            s(find,1) = image_value * w;
        end 
    end
    index_1 = index_1+1;
end
% 计算每个权重使用的次数，并且乘他们的0-8的比例，目的是统计归一化总数
sum_ = (0*sn1+0.125*sn2+0.25*sn3+0.375*sn4+0.5*sn5+0.625*sn6+0.75*sn7+0.875*sn8+1*sn9)*max;   % 整个图像用到的所有权重的总和
output = fix(sum(s)./sum_);                                                                   % 实现权重的归一化求和
