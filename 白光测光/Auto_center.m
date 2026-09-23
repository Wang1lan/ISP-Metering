function output = Auto_center(input,ration1,ration2,ration3)

a1 = Peak_test(input,ration1,ration2);
b1 = center_test(input);

ration3 = fix(ration3 * 1024);
output = fix(((ration3 * a1) + (1024 - ration3)*b1)/1024);