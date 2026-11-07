// Static Web Apps configuration: routing, roles source and security headers.
import config from '../public/staticwebapp.config.json';

describe('staticwebapp.config.json', () => {
  it('falls back to the app for client routes but not for the API or assets', () => {
    expect(config.navigationFallback.rewrite).toBe('/index.html');
    expect(config.navigationFallback.exclude).toEqual(expect.arrayContaining(['/api/*', '/assets/*', '/.auth/*']));
  });

  it('takes roles from the API and requires sign-in except for the health check', () => {
    expect(config.auth.rolesSource).toBe('/api/roles');
    expect(config.routes[0]).toEqual({ route: '/api/health', allowedRoles: ['anonymous'] });
    expect(config.routes.at(-1)).toEqual({ route: '/*', allowedRoles: ['authenticated'] });
    expect(config.responseOverrides['401'].redirect).toContain('/.auth/login/aad');
  });

  it('signs in with the Key Vault certificate, not a client secret', () => {
    const registration: Record<string, string> = config.auth.identityProviders.azureActiveDirectory.registration;
    expect(registration.openIdIssuer).toBe('https://login.microsoftonline.com/__TENANT_ID__/v2.0');
    expect(registration.clientIdSettingName).toBe('AAD_CLIENT_ID');
    expect(registration.clientSecretCertificateKeyVaultReference).toBe(
      '@Microsoft.KeyVault(SecretUri=https://__KEY_VAULT_NAME__.vault.azure.net/certificates/rdg-signin)',
    );
    expect(registration.clientSecretCertificateThumbprint).toBe('*');
    expect(registration).not.toHaveProperty('clientSecretSettingName');
  });

  it('sends a strict content security policy', () => {
    const csp = config.globalHeaders['content-security-policy'];
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("script-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).not.toContain('unsafe-eval');
  });
});
