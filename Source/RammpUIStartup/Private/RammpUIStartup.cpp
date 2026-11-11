// RammpUIStartup.cpp
//
// Turns Remote Control web control on by default in -game and packaged builds.
//
// Outside the editor, the engine's WebRemoteControl module only starts its HTTP (30010) and
// WebSocket (30020) servers when -RCWebControlEnable is on the command line, and it checks that
// in its own StartupModule. No ini setting or console variable can override it. This module loads
// at PostConfigInit, before WebRemoteControl, and adds the flag if it is missing.
//
// Launch with -RCWebControlDisable to keep web control off.

#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Modules/ModuleManager.h"

class FRammpUIStartupModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		const TCHAR* CmdLine = FCommandLine::Get();
		if (!FParse::Param(CmdLine, TEXT("RCWebControlEnable")) && !FParse::Param(CmdLine, TEXT("RCWebControlDisable")))
		{
			FCommandLine::Append(TEXT(" -RCWebControlEnable"));
		}
	}
};

IMPLEMENT_MODULE(FRammpUIStartupModule, RammpUIStartup)
