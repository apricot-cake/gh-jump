using GHJump.Core;
using Microsoft.CommandPalette.Extensions.Toolkit;

namespace GHJump;

internal sealed partial class RepositoryListItem : ListItem
{
    internal GitHubRepository Repository { get; }

    internal RepositoryListItem(GitHubRepository repository) : base(new ActionsPage(repository))
    {
        Repository = repository;
        Title = repository.Name;
        Subtitle = repository.Owner;
        Icon = JumpIcons.Get("repo");
    }
}
