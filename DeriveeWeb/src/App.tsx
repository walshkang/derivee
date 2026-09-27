import { useEffect } from 'preact/hooks';
import { registerSW } from 'virtual:pwa-register';
import { useOnlineStatus } from './hooks/useOnlineStatus';
import { useIsIOSInstallable } from './hooks/useIsIOSInstallable';
import { Header } from './components/Header';
import { SearchBar } from './components/SearchBar';
import { MapPlaceholder } from './components/MapPlaceholder';
import { SystemInfoDrawer } from './components/SystemInfoDrawer';
import { InstallModal } from './components/InstallModal';

export function App() {
  const isOnline = useOnlineStatus();
  const { isStandalone, isOpen, openModal, closeModal } = useIsIOSInstallable();

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
        <MapPlaceholder />
      </div>

      <SystemInfoDrawer isOnline={isOnline} />

      <InstallModal
        isOpen={isOpen}
        onClose={closeModal}
      />
    </div>
  );
}
