# A：改造前连续浮点参考

来源：实施前当前磁盘源码；只将入口及内部引用增加 refA_ 前缀。
Git HEAD: 8eb8d0ab2fb5b6bf23c4c1484dc6b44ef1f2821d

| 原文件 | SHA-256 |
| --- | --- |
| float\createMeteringConfig.m | 6951c7af4495e2682876f82034e57003bee2a8648319db188ae46e0aa0288c6c |
| float\meteringPreprocess.m | 255b463f115b762d47a0ad4c4e0bd225de68ef8875e759296cfd2b2c64cb730a |
| float\regionalMetering.m | 0539a3a9c1d733be56e11700bc185ca641717c102b46c611e56095b245541992 |
| float\getCenterWeight.m | e49af68c311b413385b798d08f8b018c2ea273c0d3a0fb0eaf9c2566e505439f |
| float\peakMetering.m | 20e2fe5ba5c26a95365442da32a497d9f18ead1708c63c0b846bf5499145798a |
| float\fusionMetering.m | 77fac0db2dfbf7c64f33e24f3d0735607cd58d20357429c06935e2f840627f1c |
| float\buildFusionLUT.m | 3f8fc003a0ebcd2e32222725e1375be450e2dc979953213c8cbcba92a458eb14 |
