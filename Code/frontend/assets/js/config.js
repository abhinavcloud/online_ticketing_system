export const APP_CONFIG = {
  appName: 'Online Ticketing System',
  apiBaseUrl: 'https://<api-gateway-id>.execute-api.<region>.amazonaws.com/<stage>',
  region: '<aws-region>',
  cognitoDomain: 'https://<your-cognito-domain>.auth.<region>.amazoncognito.com',
  cognitoClientId: '<cognito-client-id>',
  redirectUri: 'https://<your-cloudfront-domain>/callback.html',
  logoutUri: 'https://<your-cloudfront-domain>/index.html',
  oauthScopes: ['openid', 'email'],
  identityProvider: 'Google',
  browsePageSize: 12,
  maxSeatSelection: 5,
  queuePollFallbackSeconds: 5,
};
