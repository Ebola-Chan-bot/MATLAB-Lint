function issues = mlint_ifEqChainSwitch(filePath)
%mlint_ifEqChainSwitch 检测 if-elseif 链中所有条件都是同一变量 == 表达式，建议改用 switch-case-otherwise。

if nargin == 0
    issues = "if-elseif 链中所有条件均为同一变量 == 表达式的规整选择判断，应改用 switch-case-otherwise";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

iix = FullTree.mtfind('Kind', 'IF').indices;
if isempty(iix)
    issues = table(issuesBuilder);
    return;
end

for ii = 1:numel(iix)
    nd = FullTree.select(iix(ii));
    startLn = double(nd.lineno);
    [endLn, ~] = pos2lc(nd, righttreepos(nd));

    [varName, branchCount] = iCheckEqPattern(FullTree, startLn, endLn);
    if strlength(varName) == 0 || branchCount < 2
        continue;
    end

    if iHasElseInBlock(FullTree, startLn, endLn)
        elseMsg = "（含 else）";
    else
        elseMsg = "";
    end

    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, startLn, "mlint_ifEqChainSwitch", ...
        sprintf(['检测到 %d 个 if-elseif 分支全部为同一变量 "%s" == 表达式的选择判断', ...
        '%s。建议改用 switch %s / case ... / otherwise 结构'], ...
        branchCount, varName, elseMsg, varName)}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function [varName, branchCount] = iCheckEqPattern(FullTree, startLn, endLn)
varName = "";
branchCount = 0;

% IFHEAD
hix = FullTree.mtfind('Kind', 'IFHEAD').indices;
if ~isempty(hix)
    for hi = 1:numel(hix)
        h = FullTree.select(hix(hi));
        hl = double(h.lineno);
        if hl >= startLn && hl <= endLn
            vn = iGetEqVariable(Left(h));
            if strlength(vn) == 0
                return;
            end
            if strlength(varName) == 0
                varName = vn;
            elseif lower(vn) ~= lower(varName)
                return;
            end
            branchCount = branchCount + 1;
        end
    end
end

% ELSEIF
eix = FullTree.mtfind('Kind', 'ELSEIF').indices;
if ~isempty(eix)
    for ei = 1:numel(eix)
        en = FullTree.select(eix(ei));
        el = double(en.lineno);
        if el >= startLn && el <= endLn
            CondNode = Left(en);
            if count(CondNode) > 0 && char(CondNode.kind) == "PARENS"
                CondNode = Arg(CondNode);
            end
            vn = iGetEqVariable(CondNode);
            if strlength(vn) == 0
                return;
            end
            if strlength(varName) == 0
                varName = vn;
            elseif lower(vn) ~= lower(varName)
                return;
            end
            branchCount = branchCount + 1;
        end
    end
end
end

% -------------------------------------------------------------------------
function vn = iGetEqVariable(left)
vn = "";
if count(left) == 0 || ~strcmp(char(left.kind), "EQ")
    return;
end
left = Left(left);
if count(left) > 0 && strcmp(char(left.kind), 'ID')
    vn = string(left.string);
end
end

% -------------------------------------------------------------------------
function tf = iHasElseInBlock(FullTree, startLn, endLn)
tf = false;
eix = FullTree.mtfind('Kind', 'ELSE').indices;
if isempty(eix)
    return;
end
for ei = 1:numel(eix)
    en = FullTree.select(eix(ei));
    if double(en.lineno) >= startLn && double(en.lineno) <= endLn
        tf = true;
        return;
    end
end
end