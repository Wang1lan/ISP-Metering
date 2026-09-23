clc;
clear;
close all;

% 以脚本所在目录定位资源，从项目根目录或 float 目录运行均可。
scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
addpath(scriptDir);
imgDir = fullfile(projectDir, 'testImg');
imgList = ["testImg_1.bmp", "testImg_2.bmp", "testImg_3.bmp", "testImg_4.bmp"];
weightFile = fullfile(projectDir, '圆形有效视场权重_16×16.txt');

img = imread(fullfile(imgDir, imgList(2)));

% 第一阶段：预处理
cfg = createMeteringConfig();
prep = meteringPreprocess(img, weightFile, cfg);

%
% 预处理参数调试
fprintf("RminBlockCnt: %d\n", prep.RminBlockCnt);
figure(1), 
subplot(1, 2, 1), imshow(prep.Y, []), title("Y");
subplot(1, 2, 2), imshow(prep.Ri), title("Ri");
%}

