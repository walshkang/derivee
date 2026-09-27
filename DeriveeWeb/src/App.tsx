import { useEffect, useState } from 'preact/hooks';
import { registerSW } from 'virtual:pwa-register';
import { useOnlineStatus } from './hooks/useOnlineStatus';
import { useIsIOSInstallable } from './hooks/useIsIOSInstallable';
import { Header } from './components/Header';
import { SearchBar } from './components/SearchBar';
import { PackInstaller } from './components/PackInstaller';
import { MapPlaceholder } from './components/MapPlaceholder';
import { SystemInfoDrawer } from './components/SystemInfoDrawer';
import { InstallModal } from './components/InstallModal';
import type { InstalledPackState } from './types/pack';

export function App() {
  const isOnline = useOnlineStatus();
  const { isStandalone, isOpen, openModal, closeModal } = useIsIOSInstallable();
  const [packState, setPackState] = useState<InstalledPackState | null>(null);

  useEffect(() => {
    if ('serviceWorker' in navigator) {
      registerSW({
        immediate: true,
        onNeedRefresh() {
          // eslint-disable-next-line no-console
          console.info('[Dérivée PWA] New content available');
        },
        onOfflineReady() {
          // eslint-disable-next-line no-console
          console.info('[Dérivée PWA] Shell precached and ready offline');
        }
      });
    }
  }, []);

  return (
    <div class="app-layout">
      <Header
        isOnline={isOnline}
        isStandalone={isStandalone}
        onOpenInstallModal={openModal}
      />

      <div class="app-content-body">
        <SearchBar />
        <PackInstaller
          onPackStateChange={setPackState}
          isOnline={isOnline}
        />
        <MapPlaceholder packState={packState} />
      </div>

      <SystemInfoDrawer isOnline={isOnline} packState={packState} />

      <InstallModal
        isOpen={isOpen}
        onClose={closeModal}
      />
    </div>
  );
}
