namespace GHJump.Core.Tests;

public sealed class NavigationTests
{
    private static readonly GitHubRepository Repository = new(1, "octo-org", "sample.repo", true, false);

    [Theory]
    [InlineData("", "https://github.com/octo-org/sample.repo")]
    [InlineData("issues/new", "https://github.com/octo-org/sample.repo/issues/new")]
    [InlineData("issues", "https://github.com/octo-org/sample.repo/issues")]
    [InlineData("compare", "https://github.com/octo-org/sample.repo/compare")]
    [InlineData("pulls", "https://github.com/octo-org/sample.repo/pulls")]
    [InlineData("actions", "https://github.com/octo-org/sample.repo/actions")]
    [InlineData("releases", "https://github.com/octo-org/sample.repo/releases")]
    [InlineData("security", "https://github.com/octo-org/sample.repo/security")]
    [InlineData("settings", "https://github.com/octo-org/sample.repo/settings")]
    public void BuildsStandardGitHubUrls(string path, string expected)
    {
        Assert.Equal(expected, RepositoryUrls.Build(Repository, path).AbsoluteUri.TrimEnd('/'));
    }

    [Fact]
    public void DefaultActionIsRepositoryTop()
    {
        Assert.Equal("top", RepositoryActions.Default.Id);
        Assert.Equal(RepositoryActions.Default, RepositoryActions.Main[0]);
        Assert.Empty(RepositoryActions.Default.Path);
    }

    [Fact]
    public void CreationPageContainsIssueAndPullRequestTargets()
    {
        Assert.Equal("issues/new", Assert.Single(RepositoryActions.Create, action => action.Id == "create-issue").Path);
        Assert.Equal("compare", Assert.Single(RepositoryActions.Create, action => action.Id == "create-pull-request").Path);
    }
}
