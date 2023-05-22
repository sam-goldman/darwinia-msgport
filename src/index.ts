import { ethers } from "ethers";
import { getMsgport, DockType } from "./msgport";
import { axelar } from "./axelar/index";
import { layerzero } from "./layerzero/index";
import { createDefaultDockSelectionStrategy } from "./DefaultDockSelectionStrategy";
import { IDockSelectionStrategy } from "./interfaces/IDockSelectionStrategy";

export { getMsgport, DockType };
export { axelar, layerzero };

async function main(): Promise<void> {
  const provider = new ethers.providers.JsonRpcProvider(
    "https://rpc.testnet.fantom.network"
  );

  const msgport = await getMsgport(
    provider,
    "0x067442c619147f73c2cCdeC5A80A3B0DBD5dff34"
  );

  const dockSelection: IDockSelectionStrategy =
    createDefaultDockSelectionStrategy(provider);

  const dock = await msgport.getDock(
    1287, // target chain id
    dockSelection
  );

  const fee = await dock.estimateFee("0x12345678");
  console.log(`cross-chain fee: ${fee} wei.`);
}

main();
