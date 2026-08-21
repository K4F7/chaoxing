import {
  nativeBackendFromModule,
  type AlarmBackend,
  type NativeAlarmModule,
} from "@chaoxinghelper/android-alarms";
import { requireOptionalNativeModule } from "expo-modules-core";

export function loadNativeAlarmModule(): NativeAlarmModule | null {
  return requireOptionalNativeModule<NativeAlarmModule>("ChaoxingAndroidAlarms");
}

export function createProductionAlarmBackend(): AlarmBackend | null {
  return nativeBackendFromModule(loadNativeAlarmModule());
}
