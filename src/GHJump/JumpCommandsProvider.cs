using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;

namespace GHJump;

public sealed partial class JumpCommandsProvider : CommandProvider, IDisposable
{
    private readonly RepositoriesPage _repositories = new();
    private readonly ICommandItem[] _commands;

    public JumpCommandsProvider()
    {
        Id = "apricot-cake.gh-jump";
        DisplayName = "GH Jump";
        Icon = JumpIcons.Get("repo");
        _commands = [new CommandItem(_repositories) { Title = "GH Jump", Subtitle = "Search repositories and open GitHub" }];
    }

    public override ICommandItem[] TopLevelCommands() => _commands;

    public override void Dispose()
    {
        _repositories.Dispose();
        base.Dispose();
    }
}
