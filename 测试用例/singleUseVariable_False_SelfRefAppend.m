function result = singleUseVariable_False_SelfRefAppend()
allLines = splitlines(string(fileread(which('singleUseVariable_False_SelfRefAppend'))));
allLines = allLines(:);
result = allLines;
end
