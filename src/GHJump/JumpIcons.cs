using Microsoft.CommandPalette.Extensions.Toolkit;

namespace GHJump;

internal static class JumpIcons
{
    internal static IconInfo App { get; } = new(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.png"));

    internal static IconInfo Get(string name) => new(
        new IconData(Path.Combine(AppContext.BaseDirectory, "Assets", "Icons", name + "-light.png")),
        new IconData(Path.Combine(AppContext.BaseDirectory, "Assets", "Icons", name + "-dark.png")));
}
