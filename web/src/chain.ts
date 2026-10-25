import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  defineChain,
  type Address,
  type Chain,
  type PublicClient,
  type WalletClient,
} from "viem";
import { base, baseSepolia } from "viem/chains";
import abis from "./abi.json";

export const abi = abis as Record<string, any>;

// VITE_NETWORK selects the deployment: "base" (mainnet, once deployed), "base-sepolia", or "fork"
// (a local anvil fork of Base Sepolia at VITE_RPC_URL, default http://127.0.0.1:8547).
export const network = ((import.meta.env.VITE_NETWORK as string | undefined) ?? "base-sepolia") as "base" | "base-sepolia" | "fork";
const files = import.meta.glob("./deployment.*.json", { eager: true, import: "default" }) as Record<string, any>;
const file = { base: "./deployment.base.json", "base-sepolia": "./deployment.sepolia.json", fork: "./deployment.fork.json" }[network];
const dep = files[file] as (Record<string, Address> & { chainId: number }) | undefined;
export const deployed = !!dep;
export const addr = (dep ?? {}) as Record<string, Address> & { chainId: number };

const rpc = (import.meta.env.VITE_RPC_URL as string | undefined) ??
  { base: "https://mainnet.base.org", "base-sepolia": "https://sepolia.base.org", fork: "http://127.0.0.1:8547" }[network];

export const chain: Chain =
  network === "base" ? { ...base, rpcUrls: { default: { http: [rpc] } } }
  : network === "base-sepolia" ? { ...baseSepolia, rpcUrls: { default: { http: [rpc] } } }
  : defineChain({ ...baseSepolia, name: "Base Sepolia (local fork)", rpcUrls: { default: { http: [rpc] } } });

export const explorer = network === "base" ? "https://basescan.org" : network === "base-sepolia" ? "https://sepolia.basescan.org" : undefined;
export const txUrl = (h: string) => (explorer ? `${explorer}/tx/${h}` : undefined);
export const addrUrl = (a: string) => (explorer ? `${explorer}/address/${a}` : undefined);

export const publicClient: PublicClient = createPublicClient({ chain, transport: http(rpc) }) as PublicClient;

/** Switches the wallet to the game's network, adding it when the wallet does not know it. */
export async function ensureChain(wallet: WalletClient) {
  const current = await wallet.getChainId();
  if (current === chain.id) return true;
  try {
    await wallet.switchChain({ id: chain.id });
  } catch (e: any) {
    if (e?.code === 4902 || /unrecognized|not been added|unknown chain/i.test(String(e?.message))) {
      await wallet.addChain({ chain });
    } else {
      throw e;
    }
  }
  return (await wallet.getChainId()) === chain.id;
}

export async function connectWallet(): Promise<{ wallet: WalletClient; account: Address }> {
  const eth = (window as any).ethereum;
  if (!eth) throw new Error("No browser wallet found. Install a wallet that supports Base, then reload.");
  const wallet = createWalletClient({ chain, transport: custom(eth) });
  const [account] = await wallet.requestAddresses();
  await ensureChain(wallet).catch(() => false);
  return { wallet, account };
}

const target = (contract: string) =>
  (contract === "vault" ? addr.grailVault : (addr as any)[contract]) as Address;

export const read = <T,>(contract: keyof typeof abis, functionName: string, args: unknown[] = []) =>
  publicClient.readContract({ address: target(contract), abi: abi[contract], functionName, args }) as Promise<T>;

export { target };
