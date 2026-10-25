import { connectorsForWallets, getDefaultConfig } from "@rainbow-me/rainbowkit";
import { coinbaseWallet, injectedWallet } from "@rainbow-me/rainbowkit/wallets";
import { createConfig, fallback, http } from "wagmi";
import { base, baseSepolia } from "wagmi/chains";

// `NEXT_PUBLIC_RPC_URL` is an optional paid primary ahead of the public list.
const primary = process.env.NEXT_PUBLIC_RPC_URL?.trim();
const withPrimary = (urls: string[]) => fallback([...(primary ? [primary] : []), ...urls].map((u) => http(u)));

/**
 * The deployment's chain comes first so RainbowKit starts on it. Without
 * `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` only browser wallets and Coinbase Wallet are offered.
 */
export function buildWagmiConfig(chainId: number) {
  const all = [baseSepolia, base] as const;
  const chains = [all.find((c) => c.id === chainId) ?? baseSepolia, ...all.filter((c) => c.id !== chainId)] as unknown as typeof all;
  const transports = {
    [baseSepolia.id]: withPrimary(["https://sepolia.base.org", "https://base-sepolia-rpc.publicnode.com"]),
    [base.id]: withPrimary(["https://mainnet.base.org", "https://base-rpc.publicnode.com"]),
  };
  const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID?.trim();
  const appName = "Draw Shapes on Base";
  if (projectId) return getDefaultConfig({ appName, projectId, chains, transports, ssr: true });
  const connectors = connectorsForWallets([{ groupName: "Wallets", wallets: [injectedWallet, coinbaseWallet] }], {
    appName,
    projectId: "unused",
  });
  return createConfig({ chains, transports, connectors, ssr: true });
}
