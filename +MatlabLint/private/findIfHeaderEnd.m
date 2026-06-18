function headerEnd = findIfHeaderEnd(startLine, endLine, AllLines)
headerEnd = startLine;

for k = startLine:endLine - 1
    if endsWith(codeLine(AllLines(k)), "...")
        headerEnd = k;
        continue;
    end
    headerEnd = k;
    break;
end
end
