const hre = require("hardhat");
const { getMsgport } = require("../helper");

async function main() {
  // Deploy receiver
  hre.changeNetwork("pangoro");
  const ExampleReceiverDapp = await hre.ethers.getContractFactory(
    "ExampleReceiverDapp"
  );
  const receiver = await ExampleReceiverDapp.deploy();
  await receiver.deployed();
  console.log(`receiver: ${receiver.address}`);

  // Send message to receiver
  const pangolinMsgportAddress = "0x3f1394274103cdc5ca842aeeC9118c512dea9A4F";
  const msgport = await getMsgport("pangolin", pangolinMsgportAddress);
  msgport.send(receiver.address, "0x12345678");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
