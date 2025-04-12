
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { Utils } from './Utils.sol';
import { SVGRenderer } from './SVGRenderer.sol';

contract NFTManager is ERC721, ERC721Enumerable, Ownable {
    uint256 private _nextTokenId;
    
    uint256 public constant PRICE = 0.01 ether;
    uint256 public constant MAX_NFT_ITEMS = 777;
    SVGRenderer public renderer;
    
    constructor(uint256 _reservedForTeam) ERC721("Gems Alpha v1", "GEMS") Ownable(msg.sender) {
        renderer = new SVGRenderer();
        for (uint i=0; i < _reservedForTeam; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
        }
    }
    
    modifier mintIsOpen {
        require(totalSupply() < MAX_NFT_ITEMS, "Mint has ended");
        _;
    }
    
    function safeMint(address to) public mintIsOpen payable {
        require(msg.value >= PRICE, "Insufficient funds");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }
    
    // New function to update the renderer (for future upgrades)
    function updateRenderer(address newRendererAddress) external onlyOwner {
        require(newRendererAddress != address(0), "Invalid renderer address");
        renderer = SVGRenderer(newRendererAddress);
    }
    
    // Function to add SVG to a token (convenience method)
    function addSVGToToken(uint256 tokenId, string calldata svgString) external onlyOwner {
        renderer.addSVG(tokenId, svgString);
    }
    
    // Function to batch add SVGs to tokens
    function batchAddSVGs(uint256[] calldata tokenIds, string[] calldata svgStrings) external onlyOwner {
        require(tokenIds.length == svgStrings.length, "Length mismatch");
        for (uint i = 0; i < tokenIds.length; i++) {
            renderer.addSVG(tokenIds[i], svgStrings[i]);
        }
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
 
        return renderAsDataUri(tokenId);
    }
    
    function renderAsDataUri(uint256 _tokenId) public view returns (string memory) {
        string memory svg;
        string memory attributes;
        (svg, attributes) = renderer.renderSVG(_tokenId);
        string memory image = string.concat('"image":"data:image/svg+xml;base64,', Utils.encode(bytes(svg)),'"');
    
        string memory json = string.concat(
            '{"name":"Gem #',
            Utils.toString(_tokenId),
            '","description":"Gems are virtual crystals with scientifically accurate properties. Each digital gem features authentic mineralogical traits and natural rarity, forever preserved on the blockchain. Stake your Gems in GemFunder DeFi pools or provide liquidity in AMM pools to mine rare crystal rewards, turning your mineralogical collection into a productive asset in our ecosystem.",',
            attributes,
            ',', image,
            '}'
        );
        
        return
            string.concat(
                "data:application/json;base64,",
                Utils.encode(bytes(json))
            );    
    }
    
    // The following functions are overrides required by Solidity.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
    
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    // Allow withdrawal of ETH
    function withdraw() public onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
    
    // Allow the contract to receive ETH
    receive() external payable {}
}
