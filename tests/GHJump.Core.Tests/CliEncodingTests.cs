using System.Text;

namespace GHJump.Core.Tests;

[CollectionDefinition("Console encoding", DisableParallelization = true)]
public sealed class ConsoleEncodingTestGroup;

[Collection("Console encoding")]
public sealed class CliEncodingTests
{
    [Fact]
    public async Task ReadsUtf8RepositoryJsonWhenHostUsesJapaneseCodePage()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        const string json = """[[{"id":1,"name":"repo","owner":{"login":"owner"},"private":true,"fork":false,"description":"ソフトウェア"}]]""";
        var originalEncoding = Console.OutputEncoding;
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        try
        {
            Console.OutputEncoding = Encoding.GetEncoding(932);
            var cli = new GitHubCli(executable);
            var output = await cli.RunAsync(
                ["-NoProfile", "-NonInteractive", "-Command", $"$bytes = [Text.Encoding]::UTF8.GetBytes('{json}'); [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)"],
                TestContext.Current.CancellationToken);

            Assert.Equal(json, output);
            Assert.Equal("owner/repo", Assert.Single(GitHubRepositoryProvider.ParseRepositories(output)).FullName);
        }
        finally
        {
            Console.OutputEncoding = originalEncoding;
        }
    }
}
