function sil_run(mode, doBuild)
% sil_run - SIL 一键流程：生成测试向量 → 编译 C → 运行 → 对拍
%
% 用法：sil_run()                  默认 double，含编译
%       sil_run('float')           单精度构建（验证固件常用精度下的允差）
%       sil_run('double', false)   跳过编译（已有 build/ 时只跑比对）
%
% 依赖：gcc（优先 PATH 中的 gcc，否则回退 MinGW_OpenGL 目录）

if nargin < 1 || isempty(mode),    mode    = 'double'; end
if nargin < 2 || isempty(doBuild), doBuild = true;     end
root = fullfile(fileparts(mfilename('fullpath')), '..');

%% 1) 生成测试向量
gen_tv();

%% 2) 编译
if doBuild
    [st, ~] = system('gcc --version');
    if st == 0, gcc = 'gcc';
    else,       gcc = 'D:/EnvConfig/MinGW_OpenGL/bin/gcc.exe'; end
    flags = '-std=c99 -O2 -Wall -Iinclude';
    if strcmpi(mode, 'float'), flags = [flags ' -DINS_REAL=float']; end
    bd = fullfile(root, 'build');
    if exist(bd, 'dir') ~= 7, mkdir(bd); end
    cur = pwd;  cd(root);
    ok = true;
    for t = {'test_trans', 'test_triad', 'test_mahony'}
        t = t{1};
        cmd = sprintf('"%s" %s %s %s -o %s -lm', gcc, flags, ...
                      fullfile('tests', [t '.c']), ...
                      'src/ins_math.c src/triad.c src/mahony.c', ...
                      fullfile('build', [t '.exe']));
        [st, msg] = system(cmd);
        if st ~= 0, ok = false; fprintf('[编译失败] %s\n%s\n', t, msg); end
    end
    cd(cur);
    if ~ok, error('sil_run: 编译失败，改用 sil_run(''%s'', false) 跳过编译或用 make 手动构建', mode); end
    fprintf('编译完成（%s）\n', mode);
end

%% 3) 运行 C 程序
cur = pwd;  cd(root);
for t = {'test_trans', 'test_triad', 'test_mahony'}
    t = t{1};  sfx = t(6:end);                          % 'trans' / 'triad' / 'mahony'
    cmd = sprintf('"%s" %s %s', fullfile('build', [t '.exe']), ...
                  fullfile('sil', 'data', sprintf('tv_%s_in.csv', sfx)), ...
                  fullfile('sil', 'data', sprintf('out_%s.csv', sfx)));
    [st, msg] = system(cmd);
    if st ~= 0, cd(cur); error('运行失败 %s：%s', t, msg); end
end
cd(cur);

%% 4) 对拍
tol = 1e-13;
if strcmpi(mode, 'float'), tol = 1e-4; end              % 单精度：累积量允差放宽
cmp_sil(tol, mode);
end
