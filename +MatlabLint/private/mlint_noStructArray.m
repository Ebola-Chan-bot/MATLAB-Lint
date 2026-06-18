function issues = mlint_noStructArray(filePath)
%mlint_noStructArray 基于 mtree 检测 struct 数组模式，建议改用 table。

if nargin == 0
    issues = "禁止 struct 数组（repmat+struct / 动态扩容），建议改用 table";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ---- 规则1：repmat(struct(...)) ----
cix = FullTree.mtfind('Kind', 'CALL').indices;
if ~isempty(cix)
    for i = 1:numel(cix)
        nd = FullTree.select(cix(i));
        if strcmpi(string(Left(nd).tree2str), "repmat")
            firstArg = iFirstListChild(Right(nd));
            if count(firstArg) > 0 && iIsStructCall(firstArg)
                issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                    filePath, double(nd.lineno), "mlint_noStructArray", ...
                    sprintf('发现 struct 数组写法（repmat+struct），建议改用 table：%s', ...
                    strtrim(string(nd.tree2str)))}; %#ok<AGROW>
            end
        end
    end
end

% ---- 规则2：s(end+1, ...) = struct(...) 动态扩容 ----
eix = FullTree.mtfind('Kind', 'EQUALS').indices;
if ~isempty(eix)
    for i = 1:numel(eix)
        nd = FullTree.select(eix(i));
        lhs = Left(nd);
        if count(lhs) > 0 && strcmp(char(lhs.kind), 'SUBSCR') ...
                && iHasEndPlusOne(lhs) && iIsStructCall(Right(nd))
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, double(nd.lineno), "mlint_noStructArray", ...
                sprintf('struct 数组动态扩容，建议用 table 收集结果：%s', ...
                strtrim(string(nd.tree2str)))}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function child = iFirstListChild(node)
child = node;
if count(node) == 0
    return;
end
if ismember(char(node.kind), ["ROW", "CELL", "CALL"])
    child = Arg(node);
end
end

% -------------------------------------------------------------------------
function tf = iIsStructCall(node)
tf = false;
if count(node) == 0
    return;
end
tf = strcmp(char(node.kind), "CALL") && strcmpi(string(Left(node).tree2str), "struct");
end

% -------------------------------------------------------------------------
function tf = iHasEndPlusOne(subscrNode)
tf = false;
if count(subscrNode) == 0 || count(Right(subscrNode)) == 0
    return;
end
tf = iTreeHasEndPlusOne(Right(subscrNode));
end

function tf = iTreeHasEndPlusOne(nxt)
tf = false;
if count(nxt) == 0
    return;
end
k = char(nxt.kind);
if k == "PLUS"
    l = Left(nxt);
    r = Right(nxt);
    tf = (count(l) > 0 && strcmp(char(l.kind), 'END') && count(r) > 0 ...
            && strcmp(char(r.kind), 'INT') && str2double(string(r.string)) == 1) ...
       || (count(r) > 0 && strcmp(char(r.kind), 'END') && count(l) > 0 ...
            && strcmp(char(l.kind), 'INT') && str2double(string(l.string)) == 1);
    if ~tf
        tf = iTreeHasEndPlusOne(l) || iTreeHasEndPlusOne(r);
    end
elseif k == "END"
    return;
end
if ~tf && count(Left(nxt)) > 0
    tf = iTreeHasEndPlusOne(Left(nxt));
end
if ~tf && count(Right(nxt)) > 0
    tf = iTreeHasEndPlusOne(Right(nxt));
end
if ~tf && count(Arg(nxt)) > 0
    tf = iTreeHasEndPlusOne(Arg(nxt));
end
if ~tf
    try  %#ok<TRYNC>
        nxt = Next(nxt);
        if count(nxt) > 0
            tf = iTreeHasEndPlusOne(nxt);
        end
    catch
    end
end
end



