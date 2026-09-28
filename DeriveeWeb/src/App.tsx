import { useEffect, useState, useRef } from 'preact/hooks';
import { registerSW } from 'virtual:pwa-register';
import { useOnlineStatus } from './hooks/useOnlineStatus';
import { useIsIOSInstallable } from './hooks/useIsIOSInstallable';
import { Header } from './components/Header';
import { SearchBar } from './components/SearchBar';
import { PackInstaller } from './components/PackInstaller';
import { BasemapView } from './components/BasemapView';
import { TripPlanner } from './components/TripPlanner';
import { SystemInfoDrawer } from './components/SystemInfoDrawer';
import { InstallModal } from './components/InstallModal';
import type { InstalledPackState } from './types/pack';
import { isPackDismissed, setPackDismissed } from './utils/opfs';

export function App() {
  const isOnline = useOnlineStatus();
  const { isStandalone, isOpen, openModal, closeModal } = useIsIOSInstallable();
  const [packState, setPackState] = useState<InstalledPackState | null>(null);
  const [packDismissed, setPackDismissedState] = useState<boolean>(() => isPackDismissed());
  const [packExpanded, setPackExpanded] = useState<boolean>(false);
  const contentBodyRef = useRef<HTMLDivElement | null>(null);

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

  const handleDismissPack = () => {
    setPackDismissed(true);
    setPackDismissedState(true);
    setPackExpanded(false);
  };

  const handleOpenTransitPack = () => {
    setPackDismissed(false);
    setPackDismissedState(false);
    setPackExpanded(true);
    contentBodyRef.current?.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const handleToggleExpandPack = () => {
    setPackExpanded((prev) => !prev);
  };

  const handleInstallSuccess = () => {
    setPackDismissed(false);
    setPackDismissedState(false);
    setPackExpanded(false);
  };

  return (
    <div class="app-layout">
      {/* Full-screen offline vector basemap base layer */}
      <BasemapView />

      <Header
        isOnline={isOnline}
        isStandalone={isStandalone}
        onOpenInstallModal={openModal}
      />

      <div class="app-content-body" ref={contentBodyRef}>
        <SearchBar />
        <PackInstaller
          onPackStateChange={setPackState}
          isOnline={isOnline}
          isDismissed={packDismissed}
          isExpanded={packExpanded}
          onDismiss={handleDismissPack}
          onToggleExpand={handleToggleExpandPack}
          onInstallSuccess={handleInstallSuccess}
        />
        {Boolean(packState?.isInstalled) && (
          <TripPlanner isInstalled={true} />
        )}
      </div>

      <SystemInfoDrawer
        isOnline={isOnline}
        packState={packState}
        onOpenTransitPack={handleOpenTransitPack}
      />

      <InstallModal
        isOpen={isOpen}
        onClose={closeModal}
      />
    </div>
  );
}
