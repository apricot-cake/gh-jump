using GHJump.Core;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;

namespace GHJump.Extension.Tests;

public sealed class NavigationTests
{
    private static readonly GitHubRepository Repository = new(123, "octocat", "hello-world", true, false);

    [Fact]
    public void TopLevelCommandHasStableIdentityAndOpensRepositoryPage()
    {
        using var provider = new JumpCommandsProvider();
        Assert.Equal("apricot-cake.gh-jump", provider.Id);
        Assert.Equal("GH Jump", provider.DisplayName);
        var command = Assert.Single(provider.TopLevelCommands());
        Assert.Equal("GH Jump", command.Title);
        var page = Assert.IsType<RepositoriesPage>(command.Command);
        Assert.Equal("gh-jump.repositories", page.Id);
        Assert.False((object)page is IDynamicListPage);
    }

    [Fact]
    public void EmptyActionQuerySelectsRepositoryTop()
    {
        var page = new ActionsPage(Repository);
        var first = ListHelpers.FilterList(page.GetItems(), string.Empty).First();
        Assert.Equal("Repository top", first.Title);
        Assert.IsType<OpenUrlCommand>(first.Command);
    }

    [Theory]
    [InlineData("i", "Issues")]
    [InlineData("p", "Pull requests")]
    [InlineData("a", "Actions")]
    [InlineData("c", "Create")]
    public void StandardToolkitRanksExpectedActionFirst(string query, string expected)
    {
        var page = new ActionsPage(Repository);
        var matches = ListHelpers.FilterList(page.GetItems(), query).ToArray();
        Assert.NotEmpty(matches);
        Assert.Equal(expected, matches[0].Title);
    }

    [Fact]
    public void CreateOpensChildPageWithoutExecutingAnAction()
    {
        var page = new ActionsPage(Repository);
        var create = ListHelpers.FilterList(page.GetItems(), "c").First();
        var child = Assert.IsType<ActionsPage>(create.Command);
        Assert.Equal("gh-jump.123.create", child.Id);
        Assert.Equal(["Issue", "Pull request"], child.GetItems().Select(item => item.Title));
        Assert.All(child.GetItems(), item => Assert.IsType<OpenUrlCommand>(item.Command));
    }

    [Theory]
    [InlineData("", "Issue")]
    [InlineData("i", "Issue")]
    [InlineData("p", "Pull request")]
    public void StandardToolkitFiltersCreateActions(string query, string expected)
    {
        var page = new ActionsPage(Repository, create: true);
        Assert.Equal(expected, ListHelpers.FilterList(page.GetItems(), query).First().Title);
    }

    [Fact]
    public void FilteringDoesNotChangeCommandsOrPageItems()
    {
        var page = new ActionsPage(Repository);
        var items = page.GetItems();
        var command = items.Single(item => item.Title == "Actions").Command;
        Assert.Same(command, ListHelpers.FilterList(items, "Actions").First().Command);
        Assert.Equal(8, page.GetItems().Length);
        Assert.Equal("Repository top", page.GetItems()[0].Title);
    }

    [Theory]
    [InlineData("hello", "octocat/hello-world")]
    [InlineData("microsoft", "microsoft/PowerToys")]
    [InlineData("MICROSOFT/powertoys", "microsoft/PowerToys")]
    public void StandardToolkitSearchesRepositoryNameOwnerAndFullName(string query, string expected)
    {
        RepositoryListItem[] repositories =
        [
            new(Repository),
            new(new GitHubRepository(456, "microsoft", "PowerToys", false, false)),
            new(new GitHubRepository(789, "other", "unrelated", false, true)),
        ];
        var first = ListHelpers.FilterList(repositories, query).First();
        Assert.Equal(expected, first.Subtitle);
    }

    [Fact]
    public void SameNamedRepositoriesKeepDistinctOwnersAndCommands()
    {
        RepositoryListItem[] repositories =
        [
            new(new GitHubRepository(1, "alice", "api", true, false)),
            new(new GitHubRepository(2, "my-org", "api", false, false)),
        ];
        var matches = ListHelpers.FilterList(repositories, "api").ToArray();
        Assert.Equal(2, matches.Length);
        Assert.All(matches, item => Assert.Equal("api", item.Title));
        Assert.Equal(["alice/api", "my-org/api"], matches.Select(item => item.Subtitle));
        Assert.NotEqual(matches[0].Command.Id, matches[1].Command.Id);
        Assert.Equal("my-org/api", ListHelpers.FilterList(repositories, "my-org/api").First().Subtitle);
    }

    [Fact]
    public void EveryUrlActionDismissesThePalette()
    {
        var pages = new[] { new ActionsPage(Repository), new ActionsPage(Repository, create: true) };
        var commands = pages.SelectMany(page => page.GetItems()).Select(item => item.Command).OfType<OpenUrlCommand>().ToArray();
        Assert.Equal(9, commands.Length);
        Assert.All(commands, command => Assert.Equal(CommandResultKind.Dismiss, command.Result.Kind));
    }

    [Fact]
    public void EveryActionHasPackagedLightAndDarkPngIcons()
    {
        var pages = new[] { new ActionsPage(Repository), new ActionsPage(Repository, create: true) };
        Assert.All(pages.SelectMany(page => page.GetItems()), item =>
        {
            Assert.NotNull(item.Icon);
            AssertPng(item.Icon.Light);
            AssertPng(item.Icon.Dark);
        });
    }

    private static void AssertPng(IIconData icon)
    {
        Assert.NotNull(icon);
        Assert.False(string.IsNullOrWhiteSpace(icon.Icon));
        Assert.True(Path.IsPathFullyQualified(icon.Icon));
        Assert.True(File.Exists(icon.Icon), $"Missing packaged icon: {icon.Icon}");
        var signature = File.ReadAllBytes(icon.Icon).Take(8).ToArray();
        Assert.Equal<byte>([137, 80, 78, 71, 13, 10, 26, 10], signature);
    }
}
