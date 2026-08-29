using System.Text.Json;

var marker = Environment.GetEnvironmentVariable("ZDB_DNX_MARKER");
if (string.IsNullOrWhiteSpace(marker)) return 2;
var data = new
{
    executed = true,
    utc = DateTimeOffset.UtcNow,
    processPath = Environment.ProcessPath,
    currentDirectory = Environment.CurrentDirectory,
    commandLine = Environment.CommandLine,
    fakeSentinelPresent = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ZDB_FAKE_SENTINEL"))
};
var path = Path.GetFullPath(marker);
Directory.CreateDirectory(Path.GetDirectoryName(path)!);
await File.WriteAllTextAsync(path, JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine("ZDB_GENERIC_LOCAL_TOOL_EXECUTED");
return 0;
