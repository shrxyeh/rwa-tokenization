/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config) => {
    config.externals.push('pino-pretty', 'lokijs', 'encoding');
    config.resolve.alias['@react-native-async-storage/async-storage'] = false;
    return config;
  },
};

export default nextConfig;
