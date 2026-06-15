function headerEnd = findIfHeaderEnd(startLine, endLine, lines)
headerEnd = startLine;

for k = startLine:endLine - 1
    code = codeLine(lines(k));
    if endsWith(code, "...")
        headerEnd = k;
        continue;
    end
    headerEnd = k;
    break;
end
end
