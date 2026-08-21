declare module "@react-native-cookies/cookies" {
  type Cookie = {
    name?: string;
    value?: string;
    domain?: string;
    path?: string;
    secure?: boolean;
    httpOnly?: boolean;
  };

  const CookieManager: {
    get(url: string, useWebKit?: boolean): Promise<Record<string, Cookie>>;
    getAll(useWebKit?: boolean): Promise<Record<string, Cookie>>;
    clearAll(useWebKit?: boolean): Promise<boolean>;
  };

  export default CookieManager;
}
