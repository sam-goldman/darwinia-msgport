const hre = require("hardhat");
const { getMsgport } = require("../helper");

function buildEstimateFeeFunction(network, endpointAddress) {
  hre.changeNetwork(network);
  const abi = ["function fee() public view returns (uint128)"];
  const messageEndpoint = new hre.ethers.Contract(
    endpointAddress,
    abi,
    hre.ethers.provider
  );
  return async (_fromDappAddress, _toDappAddress, _messagePayload) => {
    return await messageEndpoint.fee();
  };
}

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
  const estimateFee = buildEstimateFeeFunction(
    "pangolin",
    "0xE8C0d3dF83a07892F912a71927F4740B8e0e04ab" // pangolin endpoint address
  );
  const pangolinMsgportAddress = "0x3f1394274103cdc5ca842aeeC9118c512dea9A4F";
  const msgport = await getMsgport("pangolin", pangolinMsgportAddress);
  msgport.send(receiver.address, "0x12345678", estimateFee);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
