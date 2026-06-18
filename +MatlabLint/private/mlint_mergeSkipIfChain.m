function issues = mlint_mergeSkipIfChain(filePath)
%mlint_mergeSkipIfChain 连续内容相同且末尾跳出的 if 链应合并。

if nargin == 0
    issues = "连续内容相同且最后一步为跳出（continue/break/return）的 if 链应合并";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

nLines = numel(AllLines);
i = 1;
while i <= nLines
    s = strtrim(char(AllLines(i)));
    if isempty(s) || startsWith(s, '%')
        i = i + 1;
        continue;
    end

    [ok, blockEnd, skipAction, bodyPrefixKey] = iParseSimpleSkipIfBlock(i, AllLines, nLines);
    if ~ok
        i = i + 1;
        continue;
    end

    chainStart = i;
    chainEnd = blockEnd;
    chainCount = 1;
    j = blockEnd + 1;

    while j <= nLines
        sj = strtrim(char(AllLines(j)));
        if isempty(sj) || startsWith(sj, '%')
            j = j + 1;
            continue;
        end

        [ok2, blockEnd2, skipAction2, bodyPrefixKey2] = iParseSimpleSkipIfBlock(j, AllLines, nLines);
        if ~ok2 || skipAction2 ~= skipAction || bodyPrefixKey2 ~= bodyPrefixKey
            break;
        end

        chainCount = chainCount + 1;
        chainEnd = blockEnd2;
        j = blockEnd2 + 1;
    end

    if chainCount >= 2
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, chainStart, "mlint_mergeSkipIfChain", ...
            sprintf('检测到 %d 个连续 if 块内容相同且最后一步均为 %s（第 %d-%d 行），建议用短路逻辑合并条件', ...
            chainCount, char(skipAction), chainStart, chainEnd)}; %#ok<AGROW>
    end

    i = chainEnd + 1;
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function [ok, endLine, skipAction, bodyPrefixKey] = iParseSimpleSkipIfBlock(headerEnd, AllLines, nLines)
ok = false;
endLine = 0;
skipAction = "";
bodyPrefixKey = "";

if headerEnd < 1 || headerEnd > nLines || ...
   ~startsWith(codeLine(AllLines(headerEnd)), "if ")
    return;
end

depth = 0;
for k = headerEnd:nLines
    sk = strtrim(char(AllLines(k)));
    if isempty(sk) || startsWith(sk, '%')
        continue;
    end
    if isBlockStartLine(sk)
        depth = depth + 1;
        continue;
    end
    if strcmp(codeLine(sk), "end")
        depth = depth - 1;
        if depth == 0
            endLine = k;
            break;
        end
    end
end

if endLine == 0
    return;
end

body = MATLAB.Containers.Vector();
headerEnd = findIfHeaderEnd(headerEnd, endLine, AllLines);
for k = headerEnd + 1:endLine - 1
    sk = strtrim(char(AllLines(k)));
    if isempty(sk) || startsWith(sk, '%')
        continue;
    end
    sk = codeLine(sk);
    if startsWith(sk, "elseif ") || strcmp(sk, "else")
        return;
    end
    body.PushBack(string(sk));
end

body = string(body.Data);

if isempty(body)
    return;
end

stmt = strtrim(body(end));
if stmt == "continue" || stmt == "continue;"
    ok = true;
    skipAction = "continue";
elseif stmt == "break" || stmt == "break;"
    ok = true;
    skipAction = "break";
elseif stmt == "return" || stmt == "return;"
    ok = true;
    skipAction = "return";
else
    return;
end

bodyPrefixKey = iBuildBodyPrefixKey(body(1:end-1));
end

function key = iBuildBodyPrefixKey(prefix)
if isempty(prefix)
    key = "";
    return;
end

parts = strings(numel(prefix), 1);
for i = 1:numel(prefix)
    part = replace(lower(strtrim(string(prefix(i)))), sprintf('\t'), " ");
    while contains(part, "  ")
        part = replace(part, "  ", " ");
    end
    parts(i) = part;
end
key = strjoin(parts, "||");
end



