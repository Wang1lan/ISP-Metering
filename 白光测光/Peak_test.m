function final = Peak_test(input,ration1,ration2)

a = rgb2yuv(input,'BT709',8);
img = double(a(:,:,1));

[m,n] = size(img);                               % m=1024\n=1024
block_height = 16;
block_width = 16;

% 兼容中文字符串的写法
fileID = fopen('F:\isp\硬镜\白光测光算法\算法_峰值.txt', 'r'); 
if fileID == -1
    error('无法打开文件，请检查路径是否包含特殊字符或文件是否被占用。');
end
weight = textscan(fileID, '%s');
fclose(fileID);
weight = weight{1}; % 提取出 cell 数组

output = zeros(8040,1);
index_1 = 0;
% m-8是因为1080不够16整除
for x = 1:block_height:m-8                       % 先做垂直  
     for y = 1:block_width:n                     % 后做平行
         image_block = img(x:x+block_height-1,y:y+block_width-1);   % 得到了每个图像块
         image_value = fix(mean(mean(image_block)));                % 得到每个图像块的亮度
         find = 120 * index_1 + ( (y+15)/16);     % 这里的120表示1920/16的值
         w = str2double(cell2mat(weight(find,1)));
         output(find,1) = image_value.* w;
     end
    index_1 = index_1 + 1;
end
[output1,output2] = feak_list(output,ration1);                      % 前ration1%的像素总值和个数
[output3,output4] = feak_list(output,ration2);                      % 前ration2%的像素总值和个数

ans1 = output3 - output1;                                           % 像素值
ans2 = output4 - output2;                                           % 个数

if ans2 == 0
    final = 255;
else
    final = fix(ans1/ans2);                        % 最亮的10%像素均值
end


