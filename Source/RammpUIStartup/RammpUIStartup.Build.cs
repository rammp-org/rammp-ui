// Tiny module that loads before the engine's plugins start. See RammpUIStartup.cpp.

using UnrealBuildTool;

public class RammpUIStartup : ModuleRules
{
	public RammpUIStartup(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PrivateDependencyModuleNames.AddRange(new string[] { "Core" });
	}
}
