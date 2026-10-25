import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  defineChain,
  type Address,
  type PublicClient,
  type WalletClient,
} from "viem";
import { base } from "viem/chains";
import abis from "./abi.json";
import deployment from "./deployment.json";

export const abi = abis as Record<string, any>;
export const addr = deployment as unknown as Record<string, Address> & { chainId: number; env: string };

const rpc = (import.meta.env.VITE_RPC_URL as string | undefined) ??
  (addr.env === "base" ? "https://mainnet.base.org" : "http://127.0.0.1:8547");

export const chain =
  addr.env === "base" ? base : defineChain({ ...base, id: addr.chainId, name: `Base fork (${addr.env})`, rpcUrls: { default: { http: [rpc] } } });

export const publicClient: PublicClient = createPublicClient({ chain, transport: http(rpc) }) as PublicClient;

export async function connectWallet(): Promise<{ wallet: WalletClient; account: Address }> {
  const eth = (window as any).ethereum;
  if (!eth) throw new Error("No browser wallet found");
  const wallet = createWalletClient({ chain, transport: custom(eth) });
  const [account] = await wallet.requestAddresses();
  try {
    await wallet.switchChain({ id: chain.id });
  } catch {
    /* the wallet may not know the chain; the user can switch manually */
  }
  return { wallet, account };
}

export const read = <T,>(contract: keyof typeof abis, functionName: string, args: unknown[] = []) =>
  publicClient.readContract({
    address: (contract === "lens" ? addr.lens : contract === "vault" ? addr.grailVault : (addr as any)[contract]) as Address,
    abi: abi[contract],
    functionName,
    args,
  }) as Promise<T>;
