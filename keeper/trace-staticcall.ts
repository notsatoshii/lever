import { createPublicClient, http, encodeFunctionData, parseUnits, formatUnits, encodeAbiParameters, keccak256, toHex } from 'viem';
import { bscTestnet } from 'viem/chains';

const publicClient = createPublicClient({
  chain: bscTestnet,
  transport: http('https://data-seed-prebsc-1-s1.binance.org:8545'),
});

const ROUTER = '0xa682e96A99C1CAf7b3FE45D2c20F108866a6AA23';
const PRICE_ENGINE_V2 = '0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC';

async function main() {
  // Get the function selector the same way Solidity does
  const signature = "getMarkPrice(uint256)";
  const selector = keccak256(toHex(signature)).slice(0, 10);
  console.log('Function selector:', selector);
  
  // Encode the call exactly like Solidity does
  const encodedArgs = encodeAbiParameters(
    [{ type: 'uint256' }],
    [2n]
  );
  const calldata = selector + encodedArgs.slice(2);
  console.log('Calldata:', calldata);
  
  // Call PriceEngineV2 directly
  console.log('\n1. Direct call to PriceEngineV2...');
  try {
    const result = await publicClient.call({
      to: PRICE_ENGINE_V2,
      data: calldata as `0x${string}`,
    });
    console.log('Success! Data:', result.data);
    console.log('Data length:', (result.data?.length || 0) / 2 - 1, 'bytes');
  } catch (e: any) {
    console.log('Failed:', e.message?.slice(0, 100));
  }
  
  // Now call Router's _getMarkPrice via simulation
  // We can't call internal functions, so let's check if priceEngine address matches
  console.log('\n2. Checking Router priceEngine address...');
  const routerPriceEngine = await publicClient.readContract({
    address: ROUTER,
    abi: [{ name: 'priceEngine', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] }],
    functionName: 'priceEngine',
  });
  console.log('Router.priceEngine:', routerPriceEngine);
  console.log('Expected PRICE_ENGINE_V2:', PRICE_ENGINE_V2);
  console.log('Match:', routerPriceEngine.toLowerCase() === PRICE_ENGINE_V2.toLowerCase());
  
  // Let's try with higher gas limit simulation
  console.log('\n3. Testing openPosition with trace...');
  const USDT = '0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58';
  const trader = '0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc';
  
  // First check USDT allowance
  const allowance = await publicClient.readContract({
    address: USDT,
    abi: [{ name: 'allowance', type: 'function', stateMutability: 'view', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] }],
    functionName: 'allowance',
    args: [trader, ROUTER],
  });
  console.log('USDT allowance to Router:', formatUnits(allowance, 18));
  
  // Check USDT balance
  const balance = await publicClient.readContract({
    address: USDT,
    abi: [{ name: 'balanceOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] }],
    functionName: 'balanceOf',
    args: [trader],
  });
  console.log('USDT balance:', formatUnits(balance, 18));
}

main().catch(console.error);
