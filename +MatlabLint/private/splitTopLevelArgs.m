function args = splitTopLevelArgs(ArgText)
parts = MATLAB.DataTypes.ArrayBuilder();
startPos = 1;

dParen = 0;
dBracket = 0;
dBrace = 0;
inSingle = false;
inDouble = false;

i = 1;
n = numel(ArgText);
while i <= n
    ch = ArgText(i);
    if ch == '"'
        if ~inSingle
            if inDouble
                if i < n && ArgText(i + 1) == '"'
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
            if i < n && ArgText(i + 1) == ''''
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
        switch ch
            case '('
                dParen = dParen + 1;
            case ')'
                dParen = dParen - 1;
            case '['
                dBracket = dBracket + 1;
            case ']'
                dBracket = dBracket - 1;
            case '{'
                dBrace = dBrace + 1;
            case '}'
                dBrace = dBrace - 1;
            case ','
                if dParen == 0 && dBracket == 0 && dBrace == 0
                    parts.Append(strtrim( ArgText( startPos:i - 1 ) ));
                    startPos = i + 1;
                end
        end
    end

    i = i + 1;
end

parts.Append(strtrim( ArgText( startPos:end ) ));
args = parts.Harvest();
end
