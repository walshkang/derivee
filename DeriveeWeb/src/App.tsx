import { useEffect, useState } from 'preact/hooks';
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
import { BottomSheet } from './components/BottomSheet';
import { TransitOverlays } from './components/TransitOverlays';
import type { InstalledPackState } from './types/pack';
import { isPackDismissed, setPackDismissed } from './utils/opfs';
import { useTheme } from './hooks/useTheme';
import type { Map } from 'maplibre-gl';

export function App() {
  const isOnline = useOnlineStatus();
  const { theme, resolvedTheme, setTheme } = useTheme();
  const { isStandalone, isIOS, canPromptNative, isOpen, closeModal, promptInstall } = useIsIOSInstallable();
  const [packState, setPackState] = useState<InstalledPackState | null>(null);
  const [packDismissed, setPackDismissedState] = useState<boolean>(() => isPackDismissed());
  const [packExpanded, setPackExpanded] = useState<boolean>(false);
  const [swUpdateAvailable, setSwUpdateAvailable] = useState<(() => void) | null>(null);
  const [mapInstance, setMapInstance] = useState<Map | null>(null);
  const [focusedRouteId, setFocusedRouteId] = useState<string | null>(null);
  const [sheetDetent, setSheetDetent] = useState<number>(15);
  const [checkingUpdate, setCheckingUpdate] = useState(false);

  // Manual update check: fetch index.html, compare bundle hash with running version.
  // Returns true if an update is available (and shows the toast).
  const checkForUpdate = async (): Promise<boolean> => {
    try {
      setCheckingUpdate(true);
      const res = await fetch('/index.html', { cache: 'no-store' });
      if (!res.ok) return false;
      const html = await res.text();
      const match = html.match(/\/assets\/index-([A-Za-z0-9_-]+)\.js/);
      if (!match) return false;
      const serverBundle = match[1];
      const scripts = Array.from(document.querySelectorAll('script[src*="/assets/index-"]'));
      const currentSrc = scripts[0]?.getAttribute('src') || '';
      const currentMatch = currentSrc.match(/index-([A-Za-z0-9_-]+)\.js/);
      const currentBundle = currentMatch ? currentMatch[1] : null;
      if (currentBundle && serverBundle !== currentBundle) {
        setSwUpdateAvailable(() => () => window.location.reload());
        return true;
      }
      return false;
    } catch {
      return false;
    } finally {
      setCheckingUpdate(false);
    }
  };

  useEffect(() => {
    if ('serviceWorker' in navigator) {
      const updateSW = registerSW({
        immediate: true,
        onNeedRefresh() {
          // New version available — show update prompt instead of just logging
          setSwUpdateAvailable(() => () => {
            updateSW(true).then(() => window.location.reload());
          });
        },
        onOfflineReady() {
          // eslint-disable-next-line no-console
          console.info('[Dérivée PWA] Shell precached and ready offline');
        }
      });
    }

    // Automatic checks: on load and when tab becomes visible.
    // No interval polling — manual check button covers the rest.
    const onVisibility = () => {
      if (document.visibilityState === 'visible') checkForUpdate();
    };
    document.addEventListener('visibilitychange', onVisibility);
    const initialCheck = setTimeout(checkForUpdate, 5000);
    return () => {
      clearTimeout(initialCheck);
      document.removeEventListener('visibilitychange', onVisibility);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
      {/* Service worker update prompt */}
      {swUpdateAvailable && (
        <div class="sw-update-toast" role="alert">
          <span>New version available</span>
          <button type="button" onClick={() => swUpdateAvailable()}>
            Update
          </button>
          <button type="button" aria-label="Dismiss" onClick={() => setSwUpdateAvailable(null)}>
            ✕
          </button>
        </div>
      )}
      {/* Full-screen offline vector basemap base layer */}
      <BasemapView theme={resolvedTheme} onMapLoaded={setMapInstance} />

      <TransitOverlays
        map={mapInstance}
        isPackInstalled={Boolean(packState?.isInstalled)}
        focusedRouteId={focusedRouteId}
      />

      <Header
        isOnline={isOnline}
        isStandalone={isStandalone}
        canInstall={isIOS || canPromptNative}
        onTriggerInstall={promptInstall}
      />

      <BottomSheet
        isOpen={true}
        detents={[15, 50, 90]}
        defaultDetent={15}
        activeDetent={sheetDetent}
        onDetentChange={setSheetDetent}
        theme={theme}
        onThemeChange={setTheme}
      >
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
          <TripPlanner
            isInstalled={true}
            onFocusedRouteIdChange={setFocusedRouteId}
            onSelectLeg={(leg) => {
              if (leg && sheetDetent < 50) {
                setSheetDetent(50);
              }
            }}
          />
        )}
      </BottomSheet>

      <SystemInfoDrawer
        isOnline={isOnline}
        packState={packState}
        onOpenTransitPack={handleOpenTransitPack}
        onCheckForUpdate={checkForUpdate}
        checkingUpdate={checkingUpdate}
      />

      <InstallModal
        isOpen={isOpen}
        onClose={closeModal}
      />
    </div>
  );
}
