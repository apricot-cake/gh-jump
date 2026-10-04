namespace GHJump.Core.Tests;

public sealed class CliFailureTests
{
    [Theory]
    [InlineData("HTTP 401: Bad credentials", FailureKind.Authentication)]
    [InlineData("To get started with GitHub CLI, please run: gh auth login", FailureKind.Authentication)]
    [InlineData("HTTP 403: resource not accessible", FailureKind.Authentication)]
    [InlineData("HTTP 403: API rate limit exceeded", FailureKind.RateLimit)]
    [InlineData("failed to connect to github.com", FailureKind.Network)]
    [InlineData("HTTP 503: Service unavailable", FailureKind.Network)]
    [InlineData("unexpected failure", FailureKind.Unknown)]
    public void CategorizesFailuresWithoutExposingOriginalError(string error, FailureKind expected)
    {
        var result = GitHubCli.CategorizeFailure(error + " sensitive-private-repository-name");
        Assert.Equal(expected, result.Kind);
        Assert.DoesNotContain("sensitive-private-repository-name", result.Message);
    }

    [Fact]
    public async Task MissingExecutableProducesActionableFailure()
    {
        var cli = new GitHubCli(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "gh.exe"));
        var error = await Assert.ThrowsAsync<GitHubCliException>(() => cli.RunAsync(["api", "user"], TestContext.Current.CancellationToken));
        Assert.Equal(FailureKind.CliUnavailable, error.Kind);
    }

    [Theory]
    [InlineData("../other")]
    [InlineData("issues?token=secret")]
    [InlineData("https://malicious.example")]
    public void RejectsPathsOutsideGitHubRepository(string path)
    {
        Assert.Throws<ArgumentException>(() => RepositoryUrls.Build(new(1, "me", "repo", false, false), path));
    }
}
