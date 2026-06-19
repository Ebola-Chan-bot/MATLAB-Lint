function issues = mlint_noStructArray(filePath)
%mlint_noStructArray 基于 mtree 检测 struct 数组模式，建议改用 table。
% 覆盖：
%  1) repmat(struct(...)) — struct 数组预分配
%  2) s(end+1) = struct(...) — 动态扩容
%  3) builder.Append(struct(...)) / builder.PushBack(struct(...)) — ArrayBuilder/Vector 积累 struct

if nargin == 0
    issues = "禁止 struct 数组累积（repmat/end+1扩容/ArrayBuilder.Append/PushBack struct），应改用 MATLAB.DataTypes.InsertiveTable（struct 字段→表列），返回 table 后要求上游调用方按 table 使用";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ---- 规则1：repmat(struct(...)) ----
cix = FullTree.mtfind('Kind', 'CALL').indices;
if ~isempty(cix)
    for i = 1:numel(cix)
        nd = FullTree.select(cix(i));
        fn = string(Left(nd).tree2str);
        if ~strcmpi(strtrim(fn), "repmat"), continue; end
        firstArg = Arg(Right(nd));
        if count(firstArg) > 0 && char(firstArg.kind) == "CALL" ...
                && strcmpi(string(Left(firstArg).tree2str), "struct")
            issuesBuilder(end+1, {'file','line','rule','message'}) = ...
                {string(filePath), double(nd.lineno), "mlint_noStructArray", ...
                 "struct 数组预分配（repmat+struct），应改用 table（size 参数控制行数）"};
        end
    end
end

% ---- 扫描 ArrayBuilder/Vector 的 Append/PushBack 是否传 struct ----
% mtree 中 builder.Append(struct(...)) 是 SUBSCR 节点：
%   SUBSCR(Left=DOT(ID,Append), Right=ROW(struct(ROW(...),...)))
six = FullTree.mtfind('Kind', 'SUBSCR').indices;
for i = 1:numel(six)
    nd = FullTree.select(six(i));
    left = Left(nd);
    if count(left) == 0 || ~strcmp(char(left.kind), "DOT"), continue; end
    method = strtrim(string(Right(left).string));
    if ~ismember(method, ["Append", "PushBack"]), continue; end
    % struct 可能直接作为 Right(SUBSCR)（单参数）或嵌套在 ROW 内（多参数）
    args = Right(nd);
    if count(args) > 0
        hasStruct = false;
        if char(args.kind) == "CALL" && strcmpi(strtrim(string(Left(args).tree2str)), "struct")
            hasStruct = true;
        elseif char(args.kind) == "ROW"
            cur = Arg(args);
            while count(cur) > 0
                if char(cur.kind) == "CALL" && strcmpi(strtrim(string(Left(cur).tree2str)), "struct")
                    hasStruct = true; break;
                end
                try, cur = Next(cur); catch, break; end
            end
        end
        if hasStruct
            varName = string(Left(left).string);
            if ismissing(varName) || strlength(varName) == 0
                try
                    varName = strtrim(string(Left(left).tree2str));
                catch
                    varName = "?";
                end
            end
            varName = varName(1);
            msg = sprintf('%s.%s(struct(...)) 应改用 MATLAB.DataTypes.InsertiveTable（struct 字段→表列）', ...
                varName, method);
            %#ok<*AGROW>
            issuesBuilder(end+1, {'file','line','rule','message'}) = ...
                {string(filePath), double(nd.lineno), "mlint_noStructArray", string(msg)};
        end
    end
end

% ---- 规则2：s(end+1) = struct(...) 动态扩容 ----
eix = FullTree.mtfind('Kind', 'EQUALS').indices;
if ~isempty(eix)
    for i = 1:numel(eix)
        nd = FullTree.select(eix(i));
        lhs = Left(nd);
        if count(lhs) > 0 && strcmp(char(lhs.kind), 'SUBSCR') ...
                && contains(string(lhs.tree2str), 'end') && iIsStructCall(Right(nd))
            issuesBuilder(end+1, {'file','line','rule','message'}) = ...
                {string(filePath), double(nd.lineno), "mlint_noStructArray", ...
                 "struct 数组动态扩容（end+1），应改用 table 收集结果"};
        end
    end
end

issues = table(issuesBuilder);
end

function tf = iIsStructCall(node)
tf = false;
if count(node) == 0, return; end
tf = strcmp(char(node.kind), "CALL") && strcmpi(strtrim(string(Left(node).tree2str)), "struct");
end



