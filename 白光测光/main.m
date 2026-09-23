clc
clear all
close all

img = imread("F:\isp\硬镜\白光测光算法\rgb.bmp");

ration1 = 0;
ration2 = 10; % 百分情况
img = img(541:1620, 961:2880, :);
% imshow(img);

output = Peak_test(img,ration1,ration2);
output2 = center_test(img);
output3 = Auto_center(img,ration1,ration2,0.5);
fprintf("Peak: %d, Center: %d, Auto: %d\n", output, output2, output3);