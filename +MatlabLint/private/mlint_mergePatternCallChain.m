function issues = mlint_mergePatternCallChain(filePath)
%mlint_mergePatternCallChain 连续 startsWith/contains/endsWith 调用应合并。

if nargin == 0
    issues = "连续的 startsWith/contains/endsWith（同函数同首参数）使用 || 时，必须合并为一次调用并用 | 连接 pattern";
    return;
end

lines = splitlines(string(fileread(filePath)));
[stmts, stmtLines] = collectStatements(lines);
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(stmts)
    stmt = char(stmts(i));
    if iHasMergeablePatternCallChain(stmt)
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, stmtLines(i), "mlint_mergePatternCallChain", ...
            sprintf("检测到连续 startsWith/contains/endsWith 的 || 链。请合并为一次调用并使用 | 连接 pattern：%s", strtrim(stmt))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasMergeablePatternCallChain(stmt)
tf = false;
terms = iSplitTopLevelOr(stmt);
if numel(terms) < 2
    return;
end

prevOk = false;
prevFn = "";
prevTarget = "";
for i = 1:numel(terms)
    [ok, fn, target] = iParsePatternCallTerm(terms(i));
    if ok && prevOk && fn == prevFn && target == prevTarget
        tf = true;
        return;
    end
    prevOk = ok;
    prevFn = fn;
    prevTarget = target;
end
end

function terms = iSplitTopLevelOr(stmt)
parts = MATLAB.DataTypes.ArrayBuilder();
startPos = 1;

dParen = 0;
dBracket = 0;
dBrace = 0;
inSingle = false;
inDouble = false;

i = 1;
n = numel(stmt);
while i <= n
    ch = stmt(i);
    if ch == '"'
        if ~inSingle
            if inDouble
                if i < n && stmt(i + 1) == '"'
                    i = i + 2;
                    continue;
                end
                inDouble = false;
            else
                inDouble = true;
            end
        end
        i = i + 1;
        continue;
    end

    if ch == ''''
        if inDouble
            i = i + 1;
            continue;
        end
        if inSingle
            if i < n && stmt(i + 1) == ''''
                i = i + 2;
                continue;
            end
            inSingle = false;
        else
            inSingle = true;
        end
        i = i + 1;
        continue;
    end

    if ~inSingle && ~inDouble
        if ch == '('
            dParen = dParen + 1;
        elseif ch == ')'
            dParen = dParen - 1;
        elseif ch == '['
            dBracket = dBracket + 1;
        elseif ch == ']'
            dBracket = dBracket - 1;
        elseif ch == '{'
            dBrace = dBrace + 1;
        elseif ch == '}'
            dBrace = dBrace - 1;
        elseif ch == '|' && i < n && stmt(i + 1) == '|' && dParen == 0 && dBracket == 0 && dBrace == 0
            parts.Append(string(strtrim(stmt(startPos:i-1))));
            startPos = i + 2;
            i = i + 2;
            continue;
        end
    end

    i = i + 1;
end

parts.Append(string(strtrim(stmt(startPos:end))));
terms = string(parts.Harvest());
end

function [ok, fn, target] = iParsePatternCallTerm(term)
ok = false;
fn = "";
target = "";

s = strtrim(string(term));
if strlength(s) == 0
    return;
end

s = iUnwrapOuterParens(s);
ls = lower(s);

if startsWith(ls, "if " | "elseif " | "while ")
    if startsWith(ls, "if ")
        s = strtrim(extractAfter(s, "if "));
    elseif startsWith(ls, "elseif ")
        s = strtrim(extractAfter(s, "elseif "));
    else
        s = strtrim(extractAfter(s, "while "));
    end
    ls = lower(s);
end

if startsWith(ls, "startswith(")
    fn = "startsWith";
    openPos = strlength("startsWith") + 1;
elseif startsWith(ls, "contains(")
    fn = "contains";
    openPos = strlength("contains") + 1;
elseif startsWith(ls, "endswith(")
    fn = "endsWith";
    openPos = strlength("endsWith") + 1;
else
    return;
end

txt = char(s);
closePos = iFindMatchingParen(txt, double(openPos));
if closePos == 0 || strlength(strtrim(string(txt(closePos+1:end)))) > 0
    return;
end

args = splitTopLevelArgs(txt(openPos+1:closePos-1));
if numel(args) < 2
    return;
end

target = iCompactArg(args(1));
if strlength(target) == 0
    return;
end

ok = true;
end

function s = iUnwrapOuterParens(in)
s = strtrim(string(in));
changed = true;
while changed
    changed = false;
    if strlength(s) < 2
        break;
    end
    txt = char(s);
    if txt(1) ~= '(' || txt(end) ~= ')'
        break;
    end
    if iFindMatchingParen(txt, 1) == numel(txt)
        s = strtrim(string(txt(2:end-1)));
        changed = true;
    end
end
end


function pos = iFindMatchingParen(txt, openPos)
pos = 0;
if openPos < 1 || openPos > numel(txt) || txt(openPos) ~= '('
    return;
end

depth = 0;
inSingle = false;
inDouble = false;

i = openPos;
n = numel(txt);
while i <= n
    ch = txt(i);
    if ch == '"'
        if ~inSingle
            if inDouble
                if i < n && txt(i + 1) == '"'
                    i = i + 2;
                    continue;
                end
                inDouble = false;
            else
                inDouble = true;
            end
        end
        i = i + 1;
        continue;
    end

    if ch == ''''
        if inDouble
            i = i + 1;
            continue;
        end
        if inSingle
            if i < n && txt(i + 1) == ''''
                i = i + 2;
                continue;
            end
            inSingle = false;
        else
            inSingle = true;
        end
        i = i + 1;
        continue;
    end

    if ~inSingle && ~inDouble
        if ch == '('
            depth = depth + 1;
        elseif ch == ')'
            depth = depth - 1;
            if depth == 0
                pos = i;
                return;
            end
        end
    end
    i = i + 1;
end
end

function out = iCompactArg(s)
out = lower(strtrim(string(s)));
out = replace(out, " ", "");
out = replace(out, sprintf('\t'), "");
end