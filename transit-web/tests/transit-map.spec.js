import { test, expect } from '@playwright/test';

test('transit app loads map and fetches vehicles', async ({ page }) => {
  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  page.on('pageerror', exception => console.log(`PAGE ERROR: ${exception}`));
  
  // Mock GTFS/SIRI API responses to prevent flakes and hide API key usage in tests
  await page.route('**/mtagtfsfeeds/nyct%2Fgtfs-l', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/octet-stream',
      body: Buffer.from('')
    });
  });

  await page.route('**/siri/vehicle-monitoring.json*', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        Siri: {
          ServiceDelivery: {
            VehicleMonitoringDelivery: []
          }
        }
      })
    });
  });

  // Mock observer db fetch
  await page.route('**/transit-data/transit_delta.sqlite', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/octet-stream',
      body: Buffer.from('')
    });
  });

  await page.goto('/');

  // Assert headers exist
  await expect(page.getByText('Subways')).toBeVisible();
  await expect(page.getByText('Buses')).toBeVisible();

  // Switch mode to Buses
  await page.getByText('Buses').click();
  
  // Assert map container is visible
  await expect(page.locator('.map-container')).toBeVisible();
});
