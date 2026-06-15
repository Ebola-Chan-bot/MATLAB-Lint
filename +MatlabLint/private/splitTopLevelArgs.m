function args = splitTopLevelArgs(text)
parts = MATLAB.DataTypes.ArrayBuilder();
startPos = 1;

dParen = 0;
dBracket = 0;
dBrace = 0;
inSingle = false;
inDouble = false;

i = 1;
n = numel(text);
while i <= n
    ch = text(i);
    if ch == '"'
        if ~inSingle
            if inDouble
                if i < n && text(i + 1) == '"'
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
            if i < n && text(i + 1) == ''''
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
        elseif ch == ',' && dParen == 0 && dBracket == 0 && dBrace == 0
            parts.Append(string(strtrim(text(startPos:i-1))));
            startPos = i + 1;
        end
    end

    i = i + 1;
end

parts.Append(string(strtrim(text(startPos:end))));
args = string(parts.Harvest());
end
