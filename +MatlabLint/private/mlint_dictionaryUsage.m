function issues = mlint_dictionaryUsage(filePath)
%mlint_dictionaryUsage dictionary 使用建议。
% 仅做简单触发检查；复杂判断放在建议文本中供手工评估。
% 1) 键类型 string → 建议检查是否均为合法标识符，若是则改用 struct
% 2) 值类型 cell → 建议检查是否均为同类型标量，若是则去掉 cell 包装
% 3) 键类型浮点数 → 建议检查是否均为整数，若是则改用整数键类型
% 4) ≥3 个同键类型 dictionary → 建议检查是否滥用，考虑合并

if nargin == 0
    issues = "dictionary 建议：1) string键→检查是否均为标识符（若是用struct）；2) cell值→检查是否均同类型标量（若是去cell包装）；3) 浮点键→检查是否均整数（若是用整数类型）；4) ≥3同类型→检查是否滥用可合并";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

declarations = iScanDeclarations(FullTree);
if isempty(declarations)
    issues = table(issuesBuilder);
    return;
end

for di = 1:size(declarations, 1)
    dLine = declarations.line(di);
    dVarName = declarations.varName(di);
    dKeyType = declarations.keyType(di);
    dValueType = declarations.valueType(di);

    if strcmp(dKeyType, 'string')
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, dLine, "mlint_dictionaryUsage", ...
            sprintf('dictionary "%s" 键类型为 string, 建议检查实际键是否均为合法标识符; 若是则改用 struct', ...
            dVarName)}; %#ok<AGROW>
    end

    if strcmp(dValueType, 'cell')
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, dLine, "mlint_dictionaryUsage", ...
            sprintf('dictionary "%s" 值类型为 cell, 建议检查实际值是否均为同类型标量; 若是则去掉 cell 包装', ...
            dVarName)}; %#ok<AGROW>
    end

    if strcmp(dKeyType, 'double') || strcmp(dKeyType, 'single')
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, dLine, "mlint_dictionaryUsage", ...
            sprintf('dictionary "%s" 键类型为浮点数 (%s), 建议检查实际键是否均为整数; 若是则改用整数键类型', ...
            dVarName, dKeyType)}; %#ok<AGROW>
    end
end

% ≥3 个同键类型可合并
ktGroups = configureDictionary('string', 'cell');
for di = 1:size(declarations, 1)
    dKeyType = declarations.keyType(di);
    dVarName = declarations.varName(di);
    dLine = declarations.line(di);
    d = struct('line', dLine, 'varName', char(dVarName), 'keyType', char(dKeyType), 'valueType', char(declarations.valueType(di)));
    kt = string(dKeyType);
    if ~isKey(ktGroups, kt)
        ktGroups(kt) = {{d}};
    else
        grp = ktGroups(kt);
        grp{1}{end+1} = d;
        ktGroups(kt) = grp;
    end
end
ktKeys = ktGroups.keys();
for ki = 1:numel(ktKeys)
    grpCell = ktGroups(ktKeys(ki));
    grp = grpCell{1};
    if numel(grp) >= 3
        names = strings(1, numel(grp));
        for gi = 1:numel(grp)
            names(gi) = grp{gi}.varName;
        end
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, grp{1}.line, "mlint_dictionaryUsage", ...
            sprintf('同一文件内有 %d 个键类型均为 "%s" 的 dictionary（%s）, 建议检查是否滥用并考虑合并', ...
            numel(grp), ktKeys(ki), strjoin(names, ", "))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function declarations = iScanDeclarations(FullTree)
builder = MATLAB.DataTypes.InsertiveTable();
declarations = table(builder);

equations = FullTree.mtfind('Kind', 'EQUALS');
if count(equations) == 0
    return;
end
eix = equations.indices;

for i = 1:numel(eix)
    nd = FullTree.select(eix(i));
    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'ID')
        continue;
    end
    varName = string(lhs.string);
    rhs = Right(nd);

    if strcmp(char(rhs.kind), 'CALL')
        fn = string(Left(rhs).tree2str);
        if fn == "configureDictionary"
            [kt, vt] = iParseConfigureDictArgs(Right(rhs));
            if strlength(kt) > 0
                builder(end+1, {'line','varName','keyType','valueType'}) = ...
                    {double(nd.lineno), varName, string(kt), string(vt)};
            end
        elseif fn == "dictionary"
            [kt, vt] = iParseDictLiteralArgs(Right(rhs));
            if strlength(kt) > 0
                builder(end+1, {'line','varName','keyType','valueType'}) = ...
                    {double(nd.lineno), varName, string(kt), string(vt)};
            end
        end
    end
end
declarations = table(builder);
end

function [keyType, valueType] = iParseConfigureDictArgs(args)
% args 是 CALL 的 Right，即第一个参数节点本身（非列表）
keyType = ""; valueType = "";
if count(args) == 0, return; end
keyType = lower(iNodeToStr(args));
if strlength(keyType) > 1
    keyType = extractBetween(keyType, 2, strlength(keyType)-1);
end
nxt = Next(args);
if count(nxt) > 0
    valueType = lower(iNodeToStr(nxt));
    if strlength(valueType) > 1
        valueType = extractBetween(valueType, 2, strlength(valueType)-1);
    end
end
end

function [keyType, valueType] = iParseDictLiteralArgs(args)
% args 是 CALL 的 Right，即第一个参数节点本身（键），Next 为值
keyType = ""; valueType = "";
if count(args) == 0, return; end
% 从第一个参数推导 key 类型
s = char(args.kind);
if strcmp(s, 'CHARVECTOR') || strcmp(s, 'STRING')
    keyType = "string";
elseif strcmp(s, 'INT') || strcmp(s, 'DOUBLE')
    keyType = "double";
end
% Next 为第一个值
nxt = Next(args);
if count(nxt) > 0
    s = char(nxt.kind);
    if strcmp(s, 'CHARVECTOR') || strcmp(s, 'STRING')
        valueType = "string";
    elseif strcmp(s, 'INT') || strcmp(s, 'DOUBLE')
        valueType = "double";
    elseif strcmp(s, "TRUE") || strcmp(s, "FALSE")
        valueType = "logical";
    end
end
end

function s = iNodeToStr(node)
s = "";
if count(node) == 0, return; end
try
    s = string(node.tree2str);
catch
    s = string(node.string);
end
s = strtrim(s);
end

