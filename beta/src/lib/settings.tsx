import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { defaultSettings, loadSettings, storeSettings, type Settings } from "@/lib/impkt";

type Ctx = {
  settings: Settings;
  update: (patch: Partial<Settings>) => void;
};

const SettingsContext = createContext<Ctx>({ settings: defaultSettings, update: () => {} });

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<Settings>(defaultSettings);

  useEffect(() => {
    setSettings(loadSettings());
  }, []);

  useEffect(() => {
    document.documentElement.classList.toggle("dark", settings.theme === "dark");
    document.documentElement.style.colorScheme = settings.theme;
  }, [settings.theme]);

  useEffect(() => {
    const root = document.documentElement;
    root.classList.remove("text-scale-large", "text-scale-xl");
    if (settings.textScale === "large") root.classList.add("text-scale-large");
    if (settings.textScale === "xl") root.classList.add("text-scale-xl");
  }, [settings.textScale]);

  useEffect(() => {
    document.documentElement.classList.toggle("reduce-motion", settings.motion === "reduced");
  }, [settings.motion]);


  const update = useCallback((patch: Partial<Settings>) => {
    setSettings((prev) => {
      const next = { ...prev, ...patch, profile: { ...prev.profile, ...(patch.profile ?? {}) } };
      storeSettings(next);
      return next;
    });
  }, []);

  return <SettingsContext.Provider value={{ settings, update }}>{children}</SettingsContext.Provider>;
}

export const useSettings = () => useContext(SettingsContext);
