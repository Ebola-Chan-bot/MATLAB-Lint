function inlineSingleCallHelpers(filePath, funcName)
%INLINESINGLECALLHELPERS 将文件中只有一处调用的辅助函数内联到调用处。
% 核心策略：实参赋值给形参，函数体不变，输出赋值回调用变量。
% MatlabLint.inlineSingleCallHelpers(filePath, funcName)

lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

% 1. 找定义
declLine = 0;
for i = 1:nLines
    s = strtrim(char(lines(i)));
    if startsWith(s, "function ") && contains(s, funcName + "(")
        declLine = i; break;
    end
end
if declLine == 0; error('找不到 %s', funcName); end

% 2. 找结束
endLine = 0; depth = 0;
blockStarts = ["function ","if ","for ","parfor ","while ","switch ","try","try "];
for i = declLine:nLines
    s = strtrim(char(lines(i)));
    if i == declLine; depth = 1;
    else
        isBlock = false;
        for bs = blockStarts
            if strcmp(s, strtrim(bs)) || startsWith(s, bs); isBlock = true; break; end
        end
        if isBlock; depth = depth + 1;
        elseif strcmp(s, "end"); depth = depth - 1; end
    end
    if depth == 0 && i > declLine; endLine = i; break; end
end
if endLine == 0; error('找不到 end'); end

bodyLines = lines(declLine+1:endLine-1);

% 3. 跳过含 return 的
for i = 1:numel(bodyLines)
    s = strtrim(char(bodyLines(i)));
    if strcmp(s, "return") || strcmp(s, "return;"); error('含 return'); end
end

% 4. 找调用点
callLine = 0; callText = "";
for i = 1:nLines
    if i >= declLine && i <= endLine; continue; end
    if contains(strtrim(char(lines(i))), funcName + "(")
        callLine = i; callText = char(lines(i)); break;
    end
end
if callLine == 0; error('找不到调用点'); end

% 5. 只处理纯独立赋值语句调用（如 x = f(...) 或 f(...)），跳过嵌入式的
callTrimmed = strtrim(callText);
fp = strfind(callTrimmed, [funcName '(']);
if isempty(fp); error('找不到调用模式'); end
fp = fp(1);
rp = iFindParen(callTrimmed, fp + strlength(funcName));
if rp == 0; error('括号不匹配'); end

before = strtrim(callTrimmed(1:fp-1));
after = strtrim(callTrimmed(rp+1:end));
% 只要求后面不包含非空白内容（除了分号）
if ~isempty(after)
    afterClean = strtrim(strrep(after, ';', ''));
    if ~isempty(afterClean)
        error('调用后有额外内容，跳过');
    end
end

% 6. 解析形参和实参
[formOuts, formIns] = iParseFuncDecl(lines(declLine));
callOuts = iParseCallOutput(callTrimmed, fp);
callArgs = iParseCallArgs(callTrimmed, fp, rp, funcName);

indent = char(extractBefore(string(callText), callTrimmed));
if isempty(indent); indent = "    "; end

% 7. 标记需要赋值的形参（仅形参≠实参且实参是简单标识符才赋值）
formalsNeedingAssign = false(numel(formIns), 1);
for idx = 1:min(numel(formIns), numel(callArgs))
    fi = strtrim(char(formIns(idx)));
    ca = strtrim(char(callArgs(idx)));
    if fi ~= ca
        if isempty(regexp(ca, '^[a-zA-Z_][a-zA-Z_0-9]*$', 'once'))
            error('形参%s与实参%s不同名但实参非简单标识符，跳过', fi, ca);
        end
        formalsNeedingAssign(idx) = true;
    end
end

% 8. 构建内联块（全用 string 拼接避免 char 数组维度问题）
blockBuilder = MATLAB.Containers.Vector();

% (a) 实参 → 形参赋值
for idx = 1:min(numel(formIns), numel(callArgs))
    if formalsNeedingAssign(idx)
        fi = string(strtrim(formIns(idx)));
        ca = string(strtrim(callArgs(idx)));
        blockBuilder.PushBack(string(indent) + fi + " = " + ca + ";");
    end
end

% (b) 函数体原样插入
for i = 1:numel(bodyLines)
    bl = string(bodyLines(i));
    blockBuilder.PushBack(string(indent) + bl);
end

% (c) 形参输出 → 调用输出赋值
for idx = 1:min(numel(formOuts), numel(callOuts))
    fo = string(strtrim(formOuts(idx)));
    co = string(strtrim(callOuts(idx)));
    if fo ~= co
        blockBuilder.PushBack(string(indent) + co + " = " + fo + ";");
    end
end

newBlock = string(blockBuilder.Data(:));

% 8. 替换
before = lines(1:callLine-1);
after = lines(callLine+1:end);
lines = [before(:); newBlock(:); after(:)];

% 9. 删除原函数定义
newDecl = declLine; newEnd = endLine;
if callLine < declLine
    shift = numel(newBlock) - 1;
    newDecl = declLine + shift;
    newEnd   = endLine   + shift;
end
keepMask = true(size(lines));
keepMask(newDecl:newEnd) = false;
lines = lines(keepMask);

% 10. 语法验证并写回
tmpFile = [filePath '.tmp_inline.m'];
fid = fopen(tmpFile, 'w');
for i = 1:numel(lines); fprintf(fid, '%s\n', lines(i)); end
fclose(fid);

mlint_msgs = checkcode(tmpFile);
ok = true;
for kk = 1:numel(mlint_msgs)
    msg = mlint_msgs(kk).message;
    if contains(msg, '非法使用保留关键字') || contains(msg, 'Parse error')
        ok = false; break;
    end
end
delete(tmpFile);

if ok
    fid = fopen(filePath, 'w');
    for i = 1:numel(lines); fprintf(fid, '%s\n', lines(i)); end
    fclose(fid);
else
    error('内联导致语法错误，已回滚');
end
end

% ===== 辅助函数 =====

function [outs, ins] = iParseFuncDecl(line)
outs = strings(0); ins = strings(0);
s = char(strtrim(string(line)));
s = char(extractAfter(string(s), "function "));
s = strtrim(s);

% 输出
if startsWith(s, '[')
    rb = strfind(s, ']');
    if ~isempty(rb)
        outs = iSplitComma(char(strtrim(extractBetween(string(s), '[', ']'))));
        s = strtrim(s(rb(1)+1:end));
    end
elseif contains(s, '=')
    eq = strfind(s, '=');
    outs = string(strtrim(s(1:eq(1)-1)));
    s = strtrim(s(eq(1)+1:end));
end

% 输入
if startsWith(s, '='); s = strtrim(s(2:end)); end
lp = strfind(s, '(');
if isempty(lp); return; end
rp = iFindParen(s, lp(1));
if rp == 0; return; end
ins = iSplitComma(char(strtrim(extractBetween(string(s), lp(1)+1, rp-1))));
end

function outs = iParseCallOutput(callTrimmed, fp)
outs = strings(0);
before = strtrim(callTrimmed(1:fp-1));
if isempty(before); return; end
if ~endsWith(before, '='); return; end
lhs = strtrim(before(1:end-1));
if startsWith(lhs, '[')
    rb = strfind(lhs, ']');
    if isempty(rb); return; end
    outs = iSplitComma(char(strtrim(extractBetween(string(lhs), '[', ']'))));
else
    outs = string(lhs);
end
end

function args = iParseCallArgs(callTrimmed, fp, rp, funcName)
args = strings(0);
openPos = fp + strlength(funcName);
inside = strtrim(callTrimmed(openPos+1 : rp-1));
if strlength(inside) == 0; return; end
args = iSplitComma(char(inside));
end

function parts = iSplitComma(s)
parts = strings(0);
if isempty(s) || (isstring(s) && strlength(s)==0); return; end
builder = MATLAB.DataTypes.ArrayBuilder();
depth = 0; start = 1;
for i = 1:numel(char(s))
    ch = s(i);
    if ch == '(' || ch == '[' || ch == '{'; depth = depth + 1;
    elseif ch == ')' || ch == ']' || ch == '}'; depth = depth - 1;
    elseif ch == ',' && depth == 0
        builder.Append(string(strtrim(s(start:i-1))));
        start = i + 1;
    end
end
builder.Append(string(strtrim(s(start:end))));
parts = string(builder.Harvest());
end

function pos = iFindParen(s, openPos)
depth = 0;
for i = openPos:numel(char(s))
    if s(i) == '('; depth = depth + 1;
    elseif s(i) == ')'; depth = depth - 1;
        if depth == 0; pos = i; return; end
    end
end
pos = 0;
end
