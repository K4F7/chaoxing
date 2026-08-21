import { hiddenLaunchCommand } from "./launch";

export const AUTOSTART_VALUE_NAME = "ChaoxingTodo";
export const AUTOSTART_RUN_KEY =
  "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";

export type AutostartStore = {
  readCommand(): Promise<string | null>;
  writeCommand(command: string): Promise<void>;
  removeCommand(): Promise<void>;
};

export class MemoryAutostartStore implements AutostartStore {
  command: string | null = null;

  async readCommand(): Promise<string | null> {
    return this.command;
  }

  async writeCommand(command: string): Promise<void> {
    this.command = command;
  }

  async removeCommand(): Promise<void> {
    this.command = null;
  }
}

export class AutostartService {
  constructor(
    private readonly store: AutostartStore,
    private readonly executablePath: string,
    private readonly supported = true,
  ) {}

  expectedCommand(): string {
    return hiddenLaunchCommand(this.executablePath);
  }

  async isEnabled(): Promise<boolean> {
    if (!this.supported) {
      return false;
    }
    return (await this.store.readCommand()) === this.expectedCommand();
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (!this.supported) {
      throw new Error("当前平台不支持开机自启");
    }
    if (enabled) {
      await this.store.writeCommand(this.expectedCommand());
    } else {
      await this.store.removeCommand();
    }
  }
}
