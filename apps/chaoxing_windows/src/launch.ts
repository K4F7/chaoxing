export const HIDDEN_LAUNCH_ARGUMENT = "--hidden";
export const SINGLE_INSTANCE_NAME = "ChaoxingTodo.SingleInstance";

export type LaunchMode = {
  hidden: boolean;
  alreadyRunning: boolean;
};

export function parseLaunchArguments(argv: readonly string[]): { hidden: boolean } {
  return { hidden: argv.includes(HIDDEN_LAUNCH_ARGUMENT) };
}

export function resolveLaunch(input: {
  argv: readonly string[];
  tryAcquire: () => boolean;
}): LaunchMode {
  const { hidden } = parseLaunchArguments(input.argv);
  const acquired = input.tryAcquire();
  return {
    hidden,
    alreadyRunning: !acquired,
  };
}

export function hiddenLaunchCommand(executablePath: string): string {
  return `"${executablePath}" ${HIDDEN_LAUNCH_ARGUMENT}`;
}
