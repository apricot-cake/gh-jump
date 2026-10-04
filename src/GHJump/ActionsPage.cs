using GHJump.Core;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;

namespace GHJump;

internal sealed partial class ActionsPage : ListPage
{
    private readonly IListItem[] _items;

    internal ActionsPage(GitHubRepository repository, bool create = false)
    {
        Id = $"gh-jump.{repository.Id}.{(create ? "create" : "actions")}";
        Title = repository.FullName + (create ? " · Create" : string.Empty);
        Name = "Open";
        Icon = JumpIcons.Get(create ? "plus" : "repo");
        PlaceholderText = create ? "Issue or Pull request" : "Issues, Pull requests, Actions, Create…";
        var actions = create ? RepositoryActions.Create : RepositoryActions.Main;
        _items = actions.Select(action => new ListItem(
            action.Id == "create"
                ? new ActionsPage(repository, create: true)
                : new OpenUrlCommand(RepositoryUrls.Build(repository, action.Path).AbsoluteUri))
        {
            Title = action.Title,
            Icon = JumpIcons.Get(action.IconName),
        }).ToArray();
    }

    public override IListItem[] GetItems() => _items;
}
