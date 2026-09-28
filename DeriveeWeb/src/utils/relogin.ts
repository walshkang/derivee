export interface ServiceWorkerRegistrationLike {
  unregister: () => Promise<boolean>;
}

interface ServiceWorkerContainerLike {
  getRegistrations: () => Promise<readonly ServiceWorkerRegistrationLike[]> | Promise<ServiceWorkerRegistrationLike[]>;
}

export interface NavigatorLike {
  serviceWorker?: ServiceWorkerContainerLike;
}

export interface LocationLike {
  href?: string;
  reload: () => void;
}

export const RELOGIN_FALLBACK_MESSAGE =
  "Please clear your browser's cached files for this site and reload.";

/**
 * Breaks out of the service worker cache by unregistering all active service
 * workers and forcing a full network reload. If service workers are not supported,
 * navigates to a cache-busted path. Re-throws failures and invokes optional
 * onError callback so errors surface visibly to the user.
 */
export async function forceRelogin(
  navigatorLike?: NavigatorLike,
  locationLike?: LocationLike,
  onError?: (message: string) => void
): Promise<void> {
  try {
    if (navigatorLike?.serviceWorker && typeof navigatorLike.serviceWorker.getRegistrations === 'function') {
      const registrations = await navigatorLike.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((reg) => reg.unregister()));
      locationLike?.reload();
    } else if (locationLike) {
      locationLike.href = `/?t=${Date.now()}`;
    }
  } catch (err) {
    onError?.(RELOGIN_FALLBACK_MESSAGE);
    throw err;
  }
}
